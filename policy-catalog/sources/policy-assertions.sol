// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {SafeConfigLockHelpers} from "credible-std/protection/safe/SafeConfigLockHelpers.sol";
import {SafeTxShapeHelpers} from "credible-std/protection/safe/SafeTxShapeHelpers.sol";

interface IVerifierGateway {
    function routes(bytes4 selector) external view returns (address verifier, bool frozen);
}

/// @title RollingOutflowCircuitBreakerAssertion
/// @notice Reusable rolling outflow protection with configurable soft or hard transaction caps.
/// @dev The adopter is the custody contract. A zero transaction cap creates a hard stop once
///      cumulative outflow crosses the configured threshold and floor.
contract RollingOutflowCircuitBreakerAssertion is Assertion {
    address public immutable TOKEN;
    uint256 public immutable THRESHOLD_BPS;
    uint256 public immutable WINDOW;
    uint256 public immutable FLOOR;
    uint256 public immutable TX_CAP_BPS;

    constructor(address token_, uint256 thresholdBps_, uint256 window_, uint256 floor_, uint256 txCapBps_) {
        require(token_ != address(0), "Outflow breaker: token zero");
        require(thresholdBps_ > 0 && thresholdBps_ < 10_000, "Outflow breaker: threshold");
        require(window_ >= 10 && window_ <= type(uint64).max, "Outflow breaker: window");
        require(txCapBps_ < thresholdBps_, "Outflow breaker: cap");
        TOKEN = token_;
        THRESHOLD_BPS = thresholdBps_;
        WINDOW = window_;
        FLOOR = floor_;
        TX_CAP_BPS = txCapBps_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        watchCumulativeOutflow(TOKEN, THRESHOLD_BPS, WINDOW, this.assertionOutflowWithinBreaker.selector);
    }

    function assertionOutflowWithinBreaker() external view {
        PhEvm.OutflowContext memory context = ph.outflowContext();
        if (context.cumulativeOutflow < FLOOR) return;

        uint256 grossOutflow;
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        address adopter = ph.getAssertionAdopter();
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == adopter && transfers[i].to != adopter) grossOutflow += transfers[i].value;
        }
        if (grossOutflow == 0) return;
        if (TX_CAP_BPS == 0) revert("Outflow breaker: hard stop");

        uint256 balance = _readBalanceAt(TOKEN, adopter, _preTx());
        if (context.tvlSnapshot != 0 && context.tvlSnapshot < balance) balance = context.tvlSnapshot;
        require(grossOutflow * 10_000 <= balance * TX_CAP_BPS, "Outflow breaker: transaction cap");
    }
}

/// @title TieredOutflowCircuitBreakerAssertion
/// @notice Reusable soft and hard rolling outflow limits, generalized from bridge and vault controls.
contract TieredOutflowCircuitBreakerAssertion is Assertion {
    address public immutable TOKEN;
    uint256 public immutable WINDOW;
    uint256 public immutable SOFT_THRESHOLD_BPS;
    uint256 public immutable HARD_THRESHOLD_BPS;
    uint256 public immutable SOFT_WITHDRAWAL_LIMIT;

    error SoftOutflowLimitExceeded(uint256 outgoing);
    error HardOutflowLimitExceeded(uint256 outgoing);

    constructor(
        address token_,
        uint256 window_,
        uint256 softThresholdBps_,
        uint256 hardThresholdBps_,
        uint256 softWithdrawalLimit_
    ) {
        require(token_ != address(0), "Tiered breaker: token zero");
        require(window_ >= 10 && window_ <= type(uint64).max, "Tiered breaker: window");
        require(softThresholdBps_ > 0 && softThresholdBps_ < hardThresholdBps_, "Tiered breaker: thresholds");
        require(hardThresholdBps_ < 10_000, "Tiered breaker: hard threshold");
        require(softWithdrawalLimit_ > 0, "Tiered breaker: soft limit");
        TOKEN = token_;
        WINDOW = window_;
        SOFT_THRESHOLD_BPS = softThresholdBps_;
        HARD_THRESHOLD_BPS = hardThresholdBps_;
        SOFT_WITHDRAWAL_LIMIT = softWithdrawalLimit_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        watchCumulativeOutflow(TOKEN, SOFT_THRESHOLD_BPS, WINDOW, this.assertSoftOutflowLimit.selector);
        watchCumulativeOutflow(TOKEN, HARD_THRESHOLD_BPS, WINDOW, this.assertHardOutflowLimit.selector);
    }

    function assertSoftOutflowLimit() external view {
        uint256 outgoing = _grossOutflow();
        if (outgoing >= SOFT_WITHDRAWAL_LIMIT) revert SoftOutflowLimitExceeded(outgoing);
    }

    function assertHardOutflowLimit() external view {
        uint256 outgoing = _grossOutflow();
        if (outgoing != 0) revert HardOutflowLimitExceeded(outgoing);
    }

    function _grossOutflow() internal view returns (uint256 outgoing) {
        address adopter = ph.getAssertionAdopter();
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == adopter && transfers[i].to != adopter) outgoing += transfers[i].value;
        }
    }
}

/// @title SafeActionPolicyAssertion
/// @notice Constructor-driven Safe transaction-shape policy for owner and module execution.
/// @dev The same contract can serve any Safe role. All target, selector, batch, approval, and
///      module rules are supplied by the policy configuration rather than hard-coded in a subclass.
contract SafeActionPolicyAssertion is SafeTxShapeHelpers {
    address public immutable EXPECTED_SAFE;

    constructor(
        address expectedSafe_,
        TargetPolicy[] memory targetPolicies_,
        SelectorPolicy[] memory selectorPolicies_,
        BatchExecutorPolicy[] memory batchExecutorPolicies_,
        ApprovalPolicy[] memory approvalPolicies_,
        bool moduleExecutionEnabled_,
        address[] memory allowedModules_
    )
        SafeTxShapeHelpers(
            targetPolicies_,
            selectorPolicies_,
            batchExecutorPolicies_,
            approvalPolicies_,
            moduleExecutionEnabled_,
            allowedModules_
        )
    {
        require(expectedSafe_ != address(0), "Safe policy: safe zero");
        EXPECTED_SAFE = expectedSafe_;
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertAllowedAction.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertAllowedAction.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(this.assertAllowedAction.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR);
    }

    function assertAllowedAction() external view {
        Action memory action = _triggeredAction();
        require(action.safe == EXPECTED_SAFE, "Safe policy: unexpected adopter");
        if (action.fromModule) _validateModuleCaller(action.module);
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);

        (bool isBatchExecutor, uint256 batchIndex) =
            _batchPolicyForAction(action.target, action.data, action.dataOffset, action.dataLength);
        if (isBatchExecutor) {
            if (action.operation != OPERATION_DELEGATECALL) revert SafeTxShapeDelegateCallBlocked(action.target);
            if (action.value != 0) {
                revert SafeTxShapeNativeValueBlocked(action.target, MULTISEND_SELECTOR, action.value);
            }
            BatchExecutorPolicy storage policy = batchExecutorPolicies[batchIndex];
            _validateMultiSendBatchPolicy(action, policy);
            _validateMultiSendTargetSelectorPolicy(action, policy);
            _validateMultiSendApprovalPolicy(action, policy);
            return;
        }

        if (action.operation == OPERATION_DELEGATECALL) revert SafeTxShapeDelegateCallBlocked(action.target);
        _validateTargetAndSelector(action);
        if (action.dataLength >= 4) _validateApproval(action, _selectorAt(action.data, action.dataOffset));
    }
}

/// @title SafeConfigurationLockAssertion
/// @notice Exact Safe owner, threshold, module, guard, fallback, and singleton lock.
contract SafeConfigurationLockAssertion is SafeConfigLockHelpers {
    bytes32 public immutable OWNER_SET_HASH;
    bytes32 public immutable MODULE_SET_HASH;
    uint256 public immutable OWNER_COUNT;
    uint256 public immutable THRESHOLD;
    address public immutable SINGLETON;
    address public immutable FALLBACK_HANDLER;
    address public immutable GUARD;
    address public immutable MODULE_GUARD;

    constructor(
        address[] memory owners_,
        uint256 threshold_,
        address singleton_,
        address fallbackHandler_,
        address guard_,
        address moduleGuard_,
        address[] memory allowedModules_
    ) {
        require(owners_.length != 0 && threshold_ != 0 && threshold_ <= owners_.length, "Safe lock: owners");
        require(singleton_ != address(0), "Safe lock: singleton");
        OWNER_SET_HASH = hashAddressSet(owners_);
        MODULE_SET_HASH = hashAddressSet(allowedModules_);
        OWNER_COUNT = owners_.length;
        THRESHOLD = threshold_;
        SINGLETON = singleton_;
        FALLBACK_HANDLER = fallbackHandler_;
        GUARD = guard_;
        MODULE_GUARD = moduleGuard_;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.assertionSafeConfigurationUnchanged.selector);
    }

    function assertionSafeConfigurationUnchanged() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.ForkId memory post = _postTx();
        require(_addressSlotAt(safe, bytes32(0), post) == SINGLETON, "Safe lock: singleton changed");
        address[] memory owners = _ownersAt(safe, post);
        require(owners.length == OWNER_COUNT && hashAddressSet(owners) == OWNER_SET_HASH, "Safe lock: owners changed");
        require(_thresholdAt(safe, post) == THRESHOLD, "Safe lock: threshold changed");
        require(hashAddressSet(_modulesAt(safe, post)) == MODULE_SET_HASH, "Safe lock: modules changed");
        require(_guardAt(safe, post) == GUARD, "Safe lock: guard changed");
        require(_moduleGuardAt(safe, post) == MODULE_GUARD, "Safe lock: module guard changed");
        require(_fallbackHandlerAt(safe, post) == FALLBACK_HANDLER, "Safe lock: fallback changed");
    }
}

/// @title UpgradeGateStateLockAssertion
/// @notice Generalized gatekeeper state lock for Safe-controlled upgrade authorities.
contract UpgradeGateStateLockAssertion is Assertion {
    bytes32 public immutable VERSION_SLOT;
    bytes32 public immutable STATUS_SLOT;
    bytes32 public immutable START_SLOT;
    bytes32 public immutable MANAGED_LENGTH_SLOT;
    bytes32 public immutable MASTER_SLOT;
    uint256 public immutable LOCKED_VERSION_ID;
    bytes4 public immutable TRIGGER_SELECTOR;

    constructor(
        address gatekeeper_,
        uint256 lockedVersionId_,
        bytes32 versionSlot_,
        bytes32 statusSlot_,
        bytes32 startSlot_,
        bytes32 managedLengthSlot_,
        bytes32 masterSlot_,
        bytes4 triggerSelector_
    ) {
        require(gatekeeper_ != address(0) && triggerSelector_ != bytes4(0), "Upgrade lock: config");
        GATEKEEPER = gatekeeper_;
        LOCKED_VERSION_ID = lockedVersionId_;
        VERSION_SLOT = versionSlot_;
        STATUS_SLOT = statusSlot_;
        START_SLOT = startSlot_;
        MANAGED_LENGTH_SLOT = managedLengthSlot_;
        MASTER_SLOT = masterSlot_;
        TRIGGER_SELECTOR = triggerSelector_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    address public immutable GATEKEEPER;

    function triggers() external view override {
        registerFnCallTrigger(this.assertUpgradeLocked.selector, TRIGGER_SELECTOR);
    }

    function assertUpgradeLocked() external view {
        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();
        uint256 actualVersion = uint256(ph.loadStateAt(GATEKEEPER, VERSION_SLOT, post));
        require(actualVersion == LOCKED_VERSION_ID, "Upgrade lock: version changed");

        uint256 preStatus = uint256(ph.loadStateAt(GATEKEEPER, STATUS_SLOT, pre));
        uint256 postStatus = uint256(ph.loadStateAt(GATEKEEPER, STATUS_SLOT, post));
        if (postStatus != 0) {
            bool sameUpgrade = postStatus == preStatus
                && ph.loadStateAt(GATEKEEPER, START_SLOT, pre) == ph.loadStateAt(GATEKEEPER, START_SLOT, post);
            require(sameUpgrade, "Upgrade lock: upgrade advanced");
        }

        address master = address(uint160(uint256(ph.loadStateAt(GATEKEEPER, MASTER_SLOT, post))));
        require(master == ph.getAssertionAdopter(), "Upgrade lock: master changed");
        require(
            ph.loadStateAt(GATEKEEPER, MANAGED_LENGTH_SLOT, pre)
                == ph.loadStateAt(GATEKEEPER, MANAGED_LENGTH_SLOT, post),
            "Upgrade lock: managed set changed"
        );
    }
}

/// @title SettlementIntegrityPinAssertion
/// @notice Constructor-driven pin for verifier, program, state-root, and data-availability calls.
contract SettlementIntegrityPinAssertion is Assertion {
    address public immutable ROUTE_VERIFIER;
    bytes32 public immutable VERIFIER_SLOT;
    bytes32 public immutable PROGRAM_SLOT;
    bytes32 public immutable STATE_ROOT_SLOT;
    bytes4 public immutable SUBMIT_BATCH_SELECTOR;
    uint256 public immutable PROOF_OFFSET_WORD;
    bytes4[] public PINNED_CALL_SELECTORS;
    bytes4[] public FORBIDDEN_CALL_SELECTORS;
    uint256 internal constant MAX_CALLS_PER_SELECTOR = 32;
    uint64 internal constant ROUTE_VIEW_GAS = 500_000;

    constructor(
        address routeVerifier_,
        bytes32 verifierSlot_,
        bytes32 programSlot_,
        bytes32 stateRootSlot_,
        bytes4 submitBatchSelector_,
        uint256 proofOffsetWord_,
        bytes4[] memory pinnedCallSelectors_,
        bytes4[] memory forbiddenCallSelectors_
    ) {
        require(submitBatchSelector_ != bytes4(0), "Settlement pin: submit selector");
        ROUTE_VERIFIER = routeVerifier_;
        VERIFIER_SLOT = verifierSlot_;
        PROGRAM_SLOT = programSlot_;
        STATE_ROOT_SLOT = stateRootSlot_;
        SUBMIT_BATCH_SELECTOR = submitBatchSelector_;
        PROOF_OFFSET_WORD = proofOffsetWord_;
        PINNED_CALL_SELECTORS = pinnedCallSelectors_;
        FORBIDDEN_CALL_SELECTORS = forbiddenCallSelectors_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertProofSystemPinned.selector);
        registerTxEndTrigger(this.assertStateRootPinned.selector);
        registerTxEndTrigger(this.assertDataAvailabilityPinned.selector);
    }

    function assertProofSystemPinned() external view {
        address app = ph.getAssertionAdopter();
        require(
            ph.loadStateAt(app, VERIFIER_SLOT, _postTx()) == ph.loadStateAt(app, VERIFIER_SLOT, _preTx()),
            "Settlement pin: verifier changed"
        );
        require(
            ph.loadStateAt(app, PROGRAM_SLOT, _postTx()) == ph.loadStateAt(app, PROGRAM_SLOT, _preTx()),
            "Settlement pin: program changed"
        );
        for (uint256 i; i < PINNED_CALL_SELECTORS.length; ++i) {
            _requireSlotsUnchangedAcross(PINNED_CALL_SELECTORS[i]);
        }
        if (ROUTE_VERIFIER == address(0)) return;

        PhEvm.TriggerCall[] memory batches = _callsTo(SUBMIT_BATCH_SELECTOR);
        for (uint256 i; i < batches.length; ++i) {
            PhEvm.ForkId memory pre = _preCall(batches[i].callId);
            address gateway = address(uint160(uint256(ph.loadStateAt(app, VERIFIER_SLOT, pre))));
            PhEvm.StaticCallResult memory route = ph.staticcallAt(
                gateway,
                abi.encodeCall(IVerifierGateway.routes, (_proofSelector(_args(batches[i])))),
                ROUTE_VIEW_GAS,
                pre
            );
            require(route.ok, "Settlement pin: route lookup failed");
            (address verifier, bool frozen) = abi.decode(route.data, (address, bool));
            require(verifier == ROUTE_VERIFIER && !frozen, "Settlement pin: route changed");
        }
    }

    function assertStateRootPinned() external view {
        require(
            ph.loadStateAt(ph.getAssertionAdopter(), STATE_ROOT_SLOT, _postTx())
                == ph.loadStateAt(ph.getAssertionAdopter(), STATE_ROOT_SLOT, _preTx()),
            "Settlement pin: root changed"
        );
    }

    function assertDataAvailabilityPinned() external view {
        for (uint256 i; i < FORBIDDEN_CALL_SELECTORS.length; ++i) {
            PhEvm.CallFilter memory filter = PhEvm.CallFilter({
                callType: 1, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
            });
            PhEvm.TriggerCall[] memory calls =
                ph.matchingCalls(ph.getAssertionAdopter(), FORBIDDEN_CALL_SELECTORS[i], filter, 1);
            require(calls.length == 0, "Settlement pin: forbidden call");
        }
    }

    function pinnedCallSelectorCount() external view returns (uint256) {
        return PINNED_CALL_SELECTORS.length;
    }

    function _callsTo(bytes4 selector) internal view returns (PhEvm.TriggerCall[] memory calls) {
        PhEvm.CallFilter memory filter = PhEvm.CallFilter({
            callType: 1, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
        calls = ph.matchingCalls(ph.getAssertionAdopter(), selector, filter, MAX_CALLS_PER_SELECTOR + 1);
        require(calls.length <= MAX_CALLS_PER_SELECTOR, "Settlement pin: too many calls");
    }

    function _args(PhEvm.TriggerCall memory call) internal view returns (bytes memory args) {
        if (call.input.length > 0) return call.input;
        bytes memory raw = ph.callinputAt(call.callId);
        if (raw.length <= 4) return new bytes(0);
        args = new bytes(raw.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = raw[i + 4];
        }
    }

    function _requireSlotsUnchangedAcross(bytes4 selector) internal view {
        address app = ph.getAssertionAdopter();
        PhEvm.TriggerCall[] memory calls = _callsTo(selector);
        for (uint256 i; i < calls.length; ++i) {
            require(
                ph.loadStateAt(app, VERIFIER_SLOT, _postCall(calls[i].callId))
                    == ph.loadStateAt(app, VERIFIER_SLOT, _preCall(calls[i].callId)),
                "Settlement pin: verifier changed"
            );
            require(
                ph.loadStateAt(app, PROGRAM_SLOT, _postCall(calls[i].callId))
                    == ph.loadStateAt(app, PROGRAM_SLOT, _preCall(calls[i].callId)),
                "Settlement pin: program changed"
            );
        }
    }

    function _proofSelector(bytes memory args) internal view returns (bytes4 selector) {
        require(args.length >= (PROOF_OFFSET_WORD + 1) * 32, "Settlement pin: malformed proof");
        uint256 offset = uint256(_word(args, PROOF_OFFSET_WORD));
        require(offset + 36 <= args.length, "Settlement pin: malformed proof");
        bytes32 head;
        assembly {
            head := mload(add(add(args, 32), offset))
        }
        // The proof selector occupies the first four bytes of the ABI word.
        // forge-lint: disable-next-line(unsafe-typecast)
        selector = bytes4(head);
    }

    function _word(bytes memory data, uint256 index) internal pure returns (bytes32 value) {
        assembly {
            value := mload(add(add(data, 32), mul(index, 32)))
        }
    }
}
