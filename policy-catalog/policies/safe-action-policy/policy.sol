// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title SafeActionPolicyAssertion
/// @notice A Safe may only make the calls its history shows it makes.
/// @dev Adopted by each Safe, with that Safe's policy as constructor arguments (rendered into
///      assertions/credible.toml). It runs on every `execTransaction` into the Safe and
///      checks each call the Safe is about to make: the call itself, or every call in a batch run
///      through an approved MultiSendCallOnly. A stolen signer quorum, a compromised signing UI or a
///      blind-signed payload can still only produce calls of an allowed shape:
///      - Allowed calls are `(target, selector)` pairs. `ANY` as the target allows the selector on
///        every contract. That is used only for calls that do nothing unless the Safe holds a role on
///        the target (claiming ownership, updating Socket limits, revoking roles), or for calls whose
///        arguments are pinned (a token sweep that may only go to another Safe). An exact rule
///        takes precedence over the wildcard, with only its own pins.
///      - Each rule caps the ETH the call may carry. `EMPTY` as the selector is a plain ETH transfer.
///      - Argument pins fix a calldata word to a value, to the Safe itself (`SELF`) or to any Derive
///        Safe (`INTERNAL`). Pin word `TARGET_WORD` pins the call target instead.
///      - ERC-20 `approve` is checked against per-(token, spender) caps instead of a rule. Setting an
///        allowance to zero is always allowed. `increaseAllowance` and `setApprovalForAll` may only
///        lower or revoke.
///      - Everything else is rejected: unknown calls, delegatecall outside the batch executors, inner
///        delegatecalls, nested batches, calls to the Safe itself (owner, threshold, module, guard,
///        fallback and singleton changes), signed gas refunds and module executions. the adopter's Safes
///        have never used modules or refunds.
///      - The ETH all calls carry together is capped per transaction.
///      Funds can still leave through allowed calls, such as a token `transfer`. The outflow
///      breakers bound how fast; this policy bounds how. Planned changes outside the policy follow
///      the agreed flow: disable, change, re-enable.
contract SafeActionPolicyAssertion is Assertion {
    struct CallRule {
        address target;
        bytes4 selector;
        uint256 maxValue;
    }

    struct ArgPin {
        address target;
        bytes4 selector;
        uint8 word;
        bytes32 value;
    }

    struct ApprovalCap {
        address token;
        address spender;
        uint256 maxAmount;
    }

    struct Pin {
        uint8 word;
        bytes32 value;
    }

    /// @notice Rule target matching every contract.
    address public constant ANY = address(0);
    /// @notice Rule selector for a call with empty calldata (a plain ETH transfer).
    bytes4 public constant EMPTY = bytes4(0);
    /// @notice Pin value standing for the adopting Safe.
    bytes32 public constant SELF = keccak256("credible.safe-policy.self");
    /// @notice Pin value standing for any address in the configured internal set.
    bytes32 public constant INTERNAL = keccak256("credible.safe-policy.internal");
    /// @notice Pin word that checks the call target instead of a calldata word.
    uint8 public constant TARGET_WORD = type(uint8).max;
    /// @notice Most calls one batch may hold; a larger batch fails closed.
    uint256 public constant MAX_BATCH_CALLS = 200;

    /// @notice Most Safe transactions one Ethereum transaction may execute; more fails closed.
    uint256 public constant MAX_EXECS_PER_TX = 8;

    bytes4 internal constant EXEC_TRANSACTION = 0x6a761202;
    bytes4 internal constant EXEC_FROM_MODULE = 0x468721a7;
    bytes4 internal constant EXEC_FROM_MODULE_RETURN_DATA = 0x5229073f;
    bytes4 internal constant MULTI_SEND = 0x8d80ff0a;
    bytes4 internal constant APPROVE = 0x095ea7b3;
    bytes4 internal constant INCREASE_ALLOWANCE = 0x39509351;
    bytes4 internal constant SET_APPROVAL_FOR_ALL = 0xa22cb465;

    uint8 internal constant CALL = 0;
    uint8 internal constant DELEGATECALL = 1;
    /// @dev Packed MultiSend entry header: operation (1), to (20), value (32), data length (32).
    uint256 internal constant ENTRY_HEADER = 85;

    /// @notice Most ETH one Safe transaction may send, summed over all of its calls.
    uint256 public immutable MAX_ETH_PER_TX;

    mapping(bytes32 key => uint256 maxValuePlusOne) internal _rules;
    mapping(bytes32 key => Pin[]) internal _pins;
    mapping(address token => mapping(address spender => uint256 capPlusOne)) internal _approvalCaps;
    mapping(address executor => bool) public isBatchExecutor;
    mapping(address account => bool) public isInternal;

    error SafeActionPolicyModuleExecutionBlocked(bytes4 entrypoint);
    error SafeActionPolicyTooManyExecutions(uint256 maxExecutions);
    error SafeActionPolicyGasRefundBlocked(uint256 gasPrice);
    error SafeActionPolicyDelegateCallBlocked(address target);
    error SafeActionPolicyInnerDelegateCallBlocked(address target);
    error SafeActionPolicyNestedBatchBlocked(address target);
    error SafeActionPolicyUnknownOperation(uint8 operation);
    error SafeActionPolicyMalformedCalldata();
    error SafeActionPolicyBatchTooLarge(uint256 maxCalls);
    error SafeActionPolicySelfCallBlocked(bytes4 selector);
    error SafeActionPolicyCallNotAllowed(address target, bytes4 selector);
    error SafeActionPolicyValueNotAllowed(address target, bytes4 selector, uint256 value, uint256 maxValue);
    error SafeActionPolicyArgumentNotAllowed(address target, bytes4 selector, uint8 word, bytes32 value);
    error SafeActionPolicyApprovalNotAllowed(address token, address spender, uint256 amount);
    error SafeActionPolicyApprovalAboveCap(address token, address spender, uint256 amount, uint256 cap);
    error SafeActionPolicyEthCapExceeded(uint256 value, uint256 cap);
    error SafeActionPolicyInvalidPolicy();

    constructor(
        address[] memory batchExecutors,
        address[] memory internalSet,
        CallRule[] memory rules,
        ArgPin[] memory pins,
        ApprovalCap[] memory approvalCaps,
        uint256 maxEthPerTx
    ) {
        for (uint256 i; i < batchExecutors.length; ++i) {
            if (batchExecutors[i] == address(0)) revert SafeActionPolicyInvalidPolicy();
            isBatchExecutor[batchExecutors[i]] = true;
        }
        for (uint256 i; i < internalSet.length; ++i) {
            isInternal[internalSet[i]] = true;
        }
        for (uint256 i; i < rules.length; ++i) {
            CallRule memory rule = rules[i];
            bytes32 key = _key(rule.target, rule.selector);
            // Approvals have their own caps, and batches are expanded rather than called.
            if (
                _rules[key] != 0 || rule.selector == APPROVE || rule.selector == INCREASE_ALLOWANCE
                    || rule.selector == SET_APPROVAL_FOR_ALL || isBatchExecutor[rule.target]
                    || rule.maxValue == type(uint256).max
            ) revert SafeActionPolicyInvalidPolicy();
            _rules[key] = rule.maxValue + 1;
        }
        for (uint256 i; i < pins.length; ++i) {
            ArgPin memory pin = pins[i];
            bytes32 key = _key(pin.target, pin.selector);
            if (_rules[key] == 0) revert SafeActionPolicyInvalidPolicy();
            _pins[key].push(Pin({word: pin.word, value: pin.value}));
        }
        for (uint256 i; i < approvalCaps.length; ++i) {
            ApprovalCap memory cap = approvalCaps[i];
            if (
                cap.token == address(0) || cap.spender == address(0) || cap.maxAmount == 0
                    || cap.maxAmount == type(uint256).max || _approvalCaps[cap.token][cap.spender] != 0
            ) revert SafeActionPolicyInvalidPolicy();
            _approvalCaps[cap.token][cap.spender] = cap.maxAmount + 1;
        }
        MAX_ETH_PER_TX = maxEthPerTx;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionSafeCallsAllowed.selector);
    }

    /// @notice Every call the Safe made in this transaction matches its policy.
    /// - Walks every successful CALL into the Safe with `execTransaction`, at any depth: one Safe
    ///   transaction, several in one transaction, or one sent through a relayer or another Safe. The
    ///   proxy's DELEGATECALL into the singleton carries the same calldata and is not counted twice.
    /// - Rejects any module execution: the adopter's Safes have no modules.
    /// - A failure names the call that broke the policy.
    function assertionSafeCallsAllowed() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.CallFilter memory frames = PhEvm.CallFilter({
            callType: 1, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
        if (ph.matchingCalls(safe, EXEC_FROM_MODULE, frames, 1).length != 0) {
            revert SafeActionPolicyModuleExecutionBlocked(EXEC_FROM_MODULE);
        }
        if (ph.matchingCalls(safe, EXEC_FROM_MODULE_RETURN_DATA, frames, 1).length != 0) {
            revert SafeActionPolicyModuleExecutionBlocked(EXEC_FROM_MODULE_RETURN_DATA);
        }
        PhEvm.TriggerCall[] memory execs = ph.matchingCalls(safe, EXEC_TRANSACTION, frames, MAX_EXECS_PER_TX + 1);
        if (execs.length > MAX_EXECS_PER_TX) revert SafeActionPolicyTooManyExecutions(MAX_EXECS_PER_TX);
        for (uint256 i; i < execs.length; ++i) {
            _checkExecTransaction(safe, ph.callinputAt(execs[i].callId));
        }
    }

    /// @dev One `execTransaction`: the Safe transaction and, for a batch, every call inside it.
    function _checkExecTransaction(address safe, bytes memory input) internal view {
        // execTransaction(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken,
        //                 refundReceiver, signatures): ten head words.
        if (input.length < 4 + 32 * 10) revert SafeActionPolicyMalformedCalldata();
        uint256 gasPrice = _word(input, 4 + 32 * 6);
        if (gasPrice != 0) revert SafeActionPolicyGasRefundBlocked(gasPrice);

        address to = _address(input, 4);
        uint256 value = _word(input, 4 + 32);
        (uint256 dataOffset, uint256 dataLength) = _bytesArg(input, 4, _word(input, 4 + 32 * 2));
        uint256 operation = _word(input, 4 + 32 * 3);

        uint256 eth;
        if (operation == CALL) {
            eth = _checkCall(safe, to, value, input, dataOffset, dataLength);
        } else if (operation == DELEGATECALL) {
            if (!isBatchExecutor[to]) revert SafeActionPolicyDelegateCallBlocked(to);
            if (value != 0) revert SafeActionPolicyValueNotAllowed(to, MULTI_SEND, value, 0);
            eth = _checkBatch(safe, input, dataOffset, dataLength);
        } else {
            revert SafeActionPolicyUnknownOperation(uint8(operation > type(uint8).max ? type(uint8).max : operation));
        }
        if (eth > MAX_ETH_PER_TX) revert SafeActionPolicyEthCapExceeded(eth, MAX_ETH_PER_TX);
    }

    /// @notice Whether `(target, selector)` has a rule, and the ETH it may carry.
    function ruleFor(address target, bytes4 selector) external view returns (bool allowed, uint256 maxValue) {
        uint256 stored = _rules[_key(target, selector)];
        return stored == 0 ? (false, 0) : (true, stored - 1);
    }

    /// @notice The approval cap for `(token, spender)`, zero if none.
    function approvalCap(address token, address spender) external view returns (uint256) {
        uint256 stored = _approvalCaps[token][spender];
        return stored == 0 ? 0 : stored - 1;
    }

    // ---------------------------------------------------------------
    //  Checks
    // ---------------------------------------------------------------

    /// @dev Expands `multiSend(bytes)` run by delegatecall from the Safe. Only canonical ABI encoding
    ///      is accepted, and the packed entries must tile the payload exactly.
    function _checkBatch(address safe, bytes memory input, uint256 dataOffset, uint256 dataLength)
        internal
        view
        returns (uint256 eth)
    {
        if (dataLength < 4 + 64 || _selectorAt(input, dataOffset) != MULTI_SEND) {
            revert SafeActionPolicyMalformedCalldata();
        }
        if (_word(input, dataOffset + 4) != 32) revert SafeActionPolicyMalformedCalldata();
        uint256 payloadLength = _word(input, dataOffset + 4 + 32);
        uint256 payload = dataOffset + 4 + 64;
        if (payloadLength > dataOffset + dataLength - payload) revert SafeActionPolicyMalformedCalldata();

        uint256 end = payload + payloadLength;
        uint256 cursor = payload;
        uint256 calls;
        while (cursor < end) {
            if (end - cursor < ENTRY_HEADER) revert SafeActionPolicyMalformedCalldata();
            uint8 operation = uint8(input[cursor]);
            address target = _packedAddress(input, cursor + 1);
            uint256 value = _word(input, cursor + 21);
            uint256 length = _word(input, cursor + 53);
            uint256 data = cursor + ENTRY_HEADER;
            if (length > end - data) revert SafeActionPolicyMalformedCalldata();
            if (++calls > MAX_BATCH_CALLS) revert SafeActionPolicyBatchTooLarge(MAX_BATCH_CALLS);
            if (operation != CALL) revert SafeActionPolicyInnerDelegateCallBlocked(target);
            if (isBatchExecutor[target]) revert SafeActionPolicyNestedBatchBlocked(target);
            // Safe 1.5.0's MultiSendCallOnly sends a zero `to` to the Safe itself.
            if (target == address(0)) target = safe;
            eth += _checkCall(safe, target, value, input, data, length);
            cursor = data + length;
        }
    }

    /// @dev One call from the Safe. Returns the ETH it carries.
    function _checkCall(address safe, address target, uint256 value, bytes memory input, uint256 offset, uint256 length)
        internal
        view
        returns (uint256)
    {
        bytes4 selector;
        if (length != 0) {
            if (length < 4) revert SafeActionPolicyMalformedCalldata();
            selector = _selectorAt(input, offset);
            // A real zero selector would collide with the plain-transfer rule.
            if (selector == EMPTY) revert SafeActionPolicyCallNotAllowed(target, selector);
        }

        if (target == safe) {
            // An empty self-call with no value only burns a nonce (Safe's "reject transaction").
            if (length == 0 && value == 0) return 0;
            revert SafeActionPolicySelfCallBlocked(selector);
        }

        if (selector == APPROVE || selector == INCREASE_ALLOWANCE || selector == SET_APPROVAL_FOR_ALL) {
            if (value != 0) revert SafeActionPolicyValueNotAllowed(target, selector, value, 0);
            _checkApproval(target, selector, input, offset, length);
            return 0;
        }

        // An exact rule takes precedence over the wildcard, together with its own pins.
        bytes32 key = _key(target, selector);
        uint256 stored = _rules[key];
        if (stored == 0) {
            key = _key(ANY, selector);
            stored = _rules[key];
        }
        if (stored == 0) revert SafeActionPolicyCallNotAllowed(target, selector);
        if (value > stored - 1) revert SafeActionPolicyValueNotAllowed(target, selector, value, stored - 1);

        _checkPins(_pins[key], safe, target, selector, input, offset, length);
        return value;
    }

    function _checkPins(
        Pin[] storage pins,
        address safe,
        address target,
        bytes4 selector,
        bytes memory input,
        uint256 offset,
        uint256 length
    ) internal view {
        for (uint256 i; i < pins.length; ++i) {
            Pin memory pin = pins[i];
            bytes32 actual;
            if (pin.word == TARGET_WORD) {
                actual = bytes32(uint256(uint160(target)));
            } else {
                uint256 at = 4 + 32 * uint256(pin.word);
                if (length < at + 32) {
                    revert SafeActionPolicyArgumentNotAllowed(target, selector, pin.word, bytes32(0));
                }
                actual = bytes32(_word(input, offset + at));
            }
            bool ok;
            if (pin.value == SELF) {
                ok = actual == bytes32(uint256(uint160(safe)));
            } else if (pin.value == INTERNAL) {
                ok = uint256(actual) >> 160 == 0 && isInternal[address(uint160(uint256(actual)))];
            } else {
                ok = actual == pin.value;
            }
            if (!ok) revert SafeActionPolicyArgumentNotAllowed(target, selector, pin.word, actual);
        }
    }

    /// @dev `approve(spender, amount)` must be zero or within the (token, spender) cap. Allowances only
    ///      go down through `increaseAllowance(spender, 0)` and `setApprovalForAll(operator, false)`.
    function _checkApproval(address token, bytes4 selector, bytes memory input, uint256 offset, uint256 length)
        internal
        view
    {
        if (length != 4 + 64) revert SafeActionPolicyMalformedCalldata();
        address spender = _address(input, offset + 4);
        uint256 amount = _word(input, offset + 36);
        if (amount == 0) return;
        uint256 stored = selector == APPROVE ? _approvalCaps[token][spender] : 0;
        if (stored == 0) revert SafeActionPolicyApprovalNotAllowed(token, spender, amount);
        if (amount > stored - 1) revert SafeActionPolicyApprovalAboveCap(token, spender, amount, stored - 1);
    }

    // ---------------------------------------------------------------
    //  Calldata reads (bounds-checked)
    // ---------------------------------------------------------------

    function _key(address target, bytes4 selector) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector));
    }

    function _word(bytes memory data, uint256 offset) internal pure returns (uint256 value) {
        if (offset > data.length || data.length - offset < 32) revert SafeActionPolicyMalformedCalldata();
        assembly {
            value := mload(add(add(data, 32), offset))
        }
    }

    function _address(bytes memory data, uint256 offset) internal pure returns (address) {
        uint256 raw = _word(data, offset);
        if (raw >> 160 != 0) revert SafeActionPolicyMalformedCalldata();
        return address(uint160(raw));
    }

    function _packedAddress(bytes memory data, uint256 offset) internal pure returns (address) {
        return address(uint160(_word(data, offset) >> 96));
    }

    function _selectorAt(bytes memory data, uint256 offset) internal pure returns (bytes4 selector) {
        if (offset > data.length || data.length - offset < 4) revert SafeActionPolicyMalformedCalldata();
        assembly {
            selector := and(mload(add(add(data, 32), offset)), shl(224, 0xffffffff))
        }
    }

    /// @dev Bounds of an ABI `bytes` argument whose head word holds `relativeOffset` from `headStart`.
    function _bytesArg(bytes memory data, uint256 headStart, uint256 relativeOffset)
        internal
        pure
        returns (uint256 offset, uint256 length)
    {
        if (relativeOffset > data.length) revert SafeActionPolicyMalformedCalldata();
        uint256 lengthAt = headStart + relativeOffset;
        length = _word(data, lengthAt);
        offset = lengthAt + 32;
        if (length > data.length - offset) revert SafeActionPolicyMalformedCalldata();
    }
}
