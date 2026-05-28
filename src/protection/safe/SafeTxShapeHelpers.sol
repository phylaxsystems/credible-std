// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {AssertionSpec} from "../../SpecRecorder.sol";
import {PhEvm} from "../../PhEvm.sol";

/// @title SafeTxShapeHelpers
/// @author Phylax Systems
/// @notice Shared decoding and policy helpers for Safe transaction-shape assertions.
abstract contract SafeTxShapeHelpers is Assertion {
    uint8 internal constant OPERATION_CALL = 0;
    uint8 internal constant OPERATION_DELEGATECALL = 1;

    uint8 public constant APPROVAL_KIND_ERC20_APPROVE = 1;
    uint8 public constant APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE = 2;
    uint8 public constant APPROVAL_KIND_ERC721_APPROVE = 3;
    uint8 public constant APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL = 4;
    uint8 public constant APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL = 5;

    bytes4 public constant EXEC_TRANSACTION_SELECTOR =
        bytes4(keccak256("execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)"));
    bytes4 public constant EXEC_TRANSACTION_FROM_MODULE_SELECTOR =
        bytes4(keccak256("execTransactionFromModule(address,uint256,bytes,uint8)"));
    bytes4 public constant EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR =
        bytes4(keccak256("execTransactionFromModuleReturnData(address,uint256,bytes,uint8)"));

    bytes4 public constant MULTISEND_SELECTOR = bytes4(keccak256("multiSend(bytes)"));
    bytes4 public constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));
    bytes4 public constant INCREASE_ALLOWANCE_SELECTOR = bytes4(keccak256("increaseAllowance(address,uint256)"));
    bytes4 public constant SET_APPROVAL_FOR_ALL_SELECTOR = bytes4(keccak256("setApprovalForAll(address,bool)"));

    uint256 internal constant MULTISEND_HEADER_LENGTH = 85;
    uint64 internal constant ALLOWANCE_READ_GAS = 500_000;

    struct TargetPolicy {
        address target;
        bool allowAnySelector;
        bool allowEmptyCalldata;
        bool allowFallbackCalldata;
        bool allowNonzeroValue;
    }

    struct SelectorPolicy {
        address target;
        bytes4 selector;
        bool allowNonzeroValue;
    }

    struct BatchExecutorPolicy {
        address executor;
        bytes4 selector;
        bool allowDelegateCall;
        uint256 maxActions;
        bool allowNested;
    }

    struct ApprovalPolicy {
        address token;
        address spender;
        uint8 kind;
        uint256 maxAmount;
        bool allowUnlimited;
    }

    struct TriggeredSafeCall {
        bytes4 selector;
        address caller;
        bytes input;
        uint256 callStart;
        uint256 callEnd;
    }

    struct OwnerTx {
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
    }

    struct ModuleTx {
        address to;
        uint256 value;
        bytes data;
        uint8 operation;
    }

    struct Action {
        address safe;
        address module;
        address target;
        uint256 value;
        bytes data;
        uint256 dataOffset;
        uint256 dataLength;
        uint8 operation;
        bool fromModule;
        bool fromBatch;
    }

    error SafeTxShapeDuplicateTarget(address target);
    error SafeTxShapeDuplicateSelector(address target, bytes4 selector);
    error SafeTxShapeDuplicateBatchExecutor(address executor, bytes4 selector);
    error SafeTxShapeDuplicateApprovalPolicy(address token, address spender, uint8 kind);
    error SafeTxShapeDuplicateModule(address module);
    error SafeTxShapeInvalidPolicy();
    error SafeTxShapeTriggeredCallNotFound(bytes4 selector, uint256 callStart);
    error SafeTxShapeUnsupportedEntrypoint(bytes4 selector);
    error SafeTxShapeModuleExecutionDisabled(address module);
    error SafeTxShapeModuleNotAllowed(address module);
    error SafeTxShapeUnknownOperation(uint8 operation);
    error SafeTxShapeDelegateCallBlocked(address target);
    error SafeTxShapeInnerDelegateCallBlocked(address target);
    error SafeTxShapeUnknownTarget(address target);
    error SafeTxShapeSelectorNotAllowed(address target, bytes4 selector);
    error SafeTxShapeCalldataTooShort(address target, uint256 length);
    error SafeTxShapeEmptyCalldataBlocked(address target);
    error SafeTxShapeFallbackCalldataBlocked(address target, uint256 length);
    error SafeTxShapeNativeValueBlocked(address target, bytes4 selector, uint256 value);
    error SafeTxShapeBatchDelegateCallNotAllowed(address executor);
    error SafeTxShapeBatchPayloadMalformed();
    error SafeTxShapeBatchTooManyActions(uint256 maxActions);
    error SafeTxShapeNestedBatchBlocked(address executor);
    error SafeTxShapeApprovalMalformed(address token, bytes4 selector);
    error SafeTxShapeApprovalTokenUnconfigured(address token, bytes4 selector);
    error SafeTxShapeApprovalSpenderNotAllowed(address token, address spender, uint8 kind);
    error SafeTxShapeApprovalUnlimitedBlocked(address token, address spender, uint8 kind);
    error SafeTxShapeApprovalAmountAboveCap(
        address token, address spender, uint8 kind, uint256 amount, uint256 maxAmount
    );
    error SafeTxShapeAllowanceReadFailed(address token, address spender);

    TargetPolicy[] public targetPolicies;
    SelectorPolicy[] public selectorPolicies;
    BatchExecutorPolicy[] public batchExecutorPolicies;
    ApprovalPolicy[] public approvalPolicies;
    address[] public allowedModules;

    mapping(address target => uint256 indexPlusOne) internal _targetPolicyIndexPlusOne;
    mapping(address target => mapping(bytes4 selector => uint256 indexPlusOne)) internal _selectorPolicyIndexPlusOne;
    mapping(address executor => mapping(bytes4 selector => uint256 indexPlusOne)) internal _batchPolicyIndexPlusOne;
    mapping(address token => mapping(address spender => mapping(uint8 kind => ApprovalPolicy))) internal
        _approvalPolicyByKey;
    mapping(address token => mapping(address spender => mapping(uint8 kind => bool))) internal _approvalPolicyExists;
    mapping(address token => mapping(uint8 kind => bool)) internal _tokenApprovalKindRegistered;
    mapping(address module => bool allowed) internal _allowedModule;

    bool public immutable moduleExecutionEnabled;

    constructor(
        TargetPolicy[] memory targetPolicies_,
        SelectorPolicy[] memory selectorPolicies_,
        BatchExecutorPolicy[] memory batchExecutorPolicies_,
        ApprovalPolicy[] memory approvalPolicies_,
        bool moduleExecutionEnabled_,
        address[] memory allowedModules_
    ) {
        if (targetPolicies_.length == 0) revert SafeTxShapeInvalidPolicy();
        if (moduleExecutionEnabled_ && allowedModules_.length == 0) revert SafeTxShapeInvalidPolicy();

        moduleExecutionEnabled = moduleExecutionEnabled_;

        _storeTargetPolicies(targetPolicies_);
        _storeSelectorPolicies(selectorPolicies_);
        _storeBatchExecutorPolicies(batchExecutorPolicies_);
        _storeApprovalPolicies(approvalPolicies_);
        _storeAllowedModules(allowedModules_);

        _registerReshiramSpec();
    }

    function targetPolicyCount() external view returns (uint256) {
        return targetPolicies.length;
    }

    function selectorPolicyCount() external view returns (uint256) {
        return selectorPolicies.length;
    }

    function batchExecutorPolicyCount() external view returns (uint256) {
        return batchExecutorPolicies.length;
    }

    function approvalPolicyCount() external view returns (uint256) {
        return approvalPolicies.length;
    }

    function allowedModuleCount() external view returns (uint256) {
        return allowedModules.length;
    }

    function _triggeredAction() internal view returns (Action memory action) {
        TriggeredSafeCall memory triggered = _resolveTriggeredSafeCall();
        address safe = ph.getAssertionAdopter();

        if (triggered.selector == EXEC_TRANSACTION_SELECTOR) {
            return _decodeOwnerAction(safe, triggered.input);
        }

        if (
            triggered.selector == EXEC_TRANSACTION_FROM_MODULE_SELECTOR
                || triggered.selector == EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR
        ) {
            return _decodeModuleAction(safe, triggered.caller, triggered.input);
        }

        revert SafeTxShapeUnsupportedEntrypoint(triggered.selector);
    }

    function _validateInnerDelegateCallPolicy(Action memory action) internal pure {
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);
        if (action.operation == OPERATION_DELEGATECALL) revert SafeTxShapeInnerDelegateCallBlocked(action.target);
    }

    function _validateInnerTargetSelectorPolicy(Action memory action) internal view {
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);
        if (action.operation == OPERATION_DELEGATECALL) return;

        _validateTargetAndSelector(action);
    }

    function _validateInnerApprovalPolicy(Action memory action) internal view {
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);
        if (action.operation == OPERATION_DELEGATECALL) return;

        if (action.dataLength < 4) return;
        _validateApproval(action, _selectorAt(action.data, action.dataOffset));
    }

    function _validateMultiSendDelegateCallPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);
            _validateInnerDelegateCallPolicy(innerAction);
            offset = nextOffset;
        }
    }

    function _validateMultiSendTargetSelectorPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);
            _validateInnerTargetSelectorPolicy(innerAction);
            offset = nextOffset;
        }
    }

    function _validateMultiSendBatchPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        uint256 actionCount;

        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);

            ++actionCount;
            if (actionCount > batchPolicy.maxActions) revert SafeTxShapeBatchTooManyActions(batchPolicy.maxActions);
            if (innerAction.operation == OPERATION_DELEGATECALL) {
                revert SafeTxShapeInnerDelegateCallBlocked(innerAction.target);
            }
            if (_isConfiguredBatchCall(
                    innerAction.target, innerAction.data, innerAction.dataOffset, innerAction.dataLength
                )) {
                revert SafeTxShapeNestedBatchBlocked(innerAction.target);
            }

            offset = nextOffset;
        }
    }

    function _validateMultiSendApprovalPolicy(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
    {
        (uint256 transactionsOffset, uint256 transactionsLength) = _multiSendTransactions(action, batchPolicy);
        uint256 offset;
        while (offset < transactionsLength) {
            (Action memory innerAction, uint256 nextOffset) =
                _readMultiSendAction(action, transactionsOffset, transactionsLength, offset);
            _validateInnerApprovalPolicy(innerAction);
            offset = nextOffset;
        }
    }

    function _multiSendTransactions(Action memory action, BatchExecutorPolicy storage batchPolicy)
        internal
        view
        returns (uint256 transactionsOffset, uint256 transactionsLength)
    {
        if (!batchPolicy.allowDelegateCall) revert SafeTxShapeBatchDelegateCallNotAllowed(action.target);

        return _decodeSingleBytesArgument(action.data, action.dataOffset, action.dataLength, batchPolicy.selector);
    }

    function _readMultiSendAction(
        Action memory parent,
        uint256 transactionsOffset,
        uint256 transactionsLength,
        uint256 offset
    ) internal pure returns (Action memory innerAction, uint256 nextOffset) {
        if (offset > transactionsLength || transactionsLength - offset < MULTISEND_HEADER_LENGTH) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        uint256 entryOffset = transactionsOffset + offset;
        uint8 operation = uint8(parent.data[entryOffset]);
        if (operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(operation);

        address target = _readPackedAddress(parent.data, entryOffset + 1);
        if (target == address(0)) target = parent.safe;

        uint256 value = _readUint256(parent.data, entryOffset + 21);
        uint256 dataLength = _readUint256(parent.data, entryOffset + 53);
        uint256 dataOffset = entryOffset + MULTISEND_HEADER_LENGTH;
        uint256 transactionsEnd = transactionsOffset + transactionsLength;
        if (dataOffset > transactionsEnd || dataLength > transactionsEnd - dataOffset) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        innerAction = Action({
            safe: parent.safe,
            module: parent.module,
            target: target,
            value: value,
            data: parent.data,
            dataOffset: dataOffset,
            dataLength: dataLength,
            operation: operation,
            fromModule: parent.fromModule,
            fromBatch: true
        });
        nextOffset = offset + MULTISEND_HEADER_LENGTH + dataLength;
    }

    function _validateTargetAndSelector(Action memory action) internal view returns (bytes4 selector) {
        if (action.target == address(0)) revert SafeTxShapeUnknownTarget(action.target);

        (bool knownTarget, uint256 targetIndex) = _targetPolicyIndex(action.target);
        if (!knownTarget) revert SafeTxShapeUnknownTarget(action.target);

        TargetPolicy storage targetPolicy = targetPolicies[targetIndex];

        if (action.dataLength == 0) {
            if (!targetPolicy.allowEmptyCalldata) revert SafeTxShapeEmptyCalldataBlocked(action.target);
            if (action.value != 0 && !targetPolicy.allowNonzeroValue) {
                revert SafeTxShapeNativeValueBlocked(action.target, bytes4(0), action.value);
            }
            return bytes4(0);
        }

        if (action.dataLength < 4) {
            if (!targetPolicy.allowFallbackCalldata) {
                revert SafeTxShapeFallbackCalldataBlocked(action.target, action.dataLength);
            }
            if (action.value != 0 && !targetPolicy.allowNonzeroValue) {
                revert SafeTxShapeNativeValueBlocked(action.target, bytes4(0), action.value);
            }
            return bytes4(0);
        }

        selector = _selectorAt(action.data, action.dataOffset);

        if (targetPolicy.allowAnySelector) {
            if (action.value != 0 && !targetPolicy.allowNonzeroValue) {
                revert SafeTxShapeNativeValueBlocked(action.target, selector, action.value);
            }
            return selector;
        }

        (bool selectorAllowed, uint256 selectorIndex) = _selectorPolicyIndex(action.target, selector);
        if (!selectorAllowed) revert SafeTxShapeSelectorNotAllowed(action.target, selector);

        if (action.value != 0 && !selectorPolicies[selectorIndex].allowNonzeroValue) {
            revert SafeTxShapeNativeValueBlocked(action.target, selector, action.value);
        }
    }

    function _validateApproval(Action memory action, bytes4 selector) internal view {
        if (selector == APPROVE_SELECTOR) {
            if (action.dataLength != 68) revert SafeTxShapeApprovalMalformed(action.target, selector);

            address spender = _readAbiAddress(action.data, action.dataOffset + 4);
            uint256 amountOrTokenId = _readUint256(action.data, action.dataOffset + 36);
            bool erc20 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC20_APPROVE);
            bool erc721 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC721_APPROVE);

            if (erc20) {
                if (amountOrTokenId == 0) return;
                _validateNumericApproval(action.target, spender, APPROVAL_KIND_ERC20_APPROVE, amountOrTokenId);
                return;
            }

            if (erc721) {
                if (spender == address(0)) return;
                _validateOperatorApproval(action.target, spender, APPROVAL_KIND_ERC721_APPROVE);
                return;
            }

            revert SafeTxShapeApprovalTokenUnconfigured(action.target, selector);
        }

        if (selector == INCREASE_ALLOWANCE_SELECTOR) {
            if (action.dataLength != 68) revert SafeTxShapeApprovalMalformed(action.target, selector);
            if (!_tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE)) {
                revert SafeTxShapeApprovalTokenUnconfigured(action.target, selector);
            }

            address spender = _readAbiAddress(action.data, action.dataOffset + 4);
            uint256 addedValue = _readUint256(action.data, action.dataOffset + 36);
            if (addedValue == 0) return;

            // `increaseAllowance(spender, addedValue)` adds to the current allowance; treating `addedValue`
            // as the final amount would let two inner calls land above `maxAmount`. Verify the post-state
            // allowance instead so the cap binds the actual final allowance after the transaction.
            _validateIncreaseAllowanceFinalState(action.safe, action.target, spender);
            return;
        }

        if (selector == SET_APPROVAL_FOR_ALL_SELECTOR) {
            if (action.dataLength != 68) revert SafeTxShapeApprovalMalformed(action.target, selector);

            bool erc721 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL);
            bool erc1155 = _tokenHasApprovalKind(action.target, APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL);
            if (!erc721 && !erc1155) revert SafeTxShapeApprovalTokenUnconfigured(action.target, selector);

            address operator = _readAbiAddress(action.data, action.dataOffset + 4);
            bool approved = _readAbiBool(action.data, action.dataOffset + 36);
            if (!approved) return;

            if (erc721 && _operatorApprovalAllowed(action.target, operator, APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL))
            {
                return;
            }
            if (
                erc1155 && _operatorApprovalAllowed(action.target, operator, APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL)
            ) {
                return;
            }

            revert SafeTxShapeApprovalSpenderNotAllowed(
                action.target,
                operator,
                erc721 ? APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL : APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL
            );
        }
    }

    function _validateNumericApproval(address token, address spender, uint8 kind, uint256 amount) internal view {
        if (!_approvalPolicyExists[token][spender][kind]) {
            revert SafeTxShapeApprovalSpenderNotAllowed(token, spender, kind);
        }

        ApprovalPolicy storage policy = _approvalPolicyByKey[token][spender][kind];
        if (amount == type(uint256).max) {
            if (!policy.allowUnlimited) revert SafeTxShapeApprovalUnlimitedBlocked(token, spender, kind);
            return;
        }

        if (amount > policy.maxAmount) {
            revert SafeTxShapeApprovalAmountAboveCap(token, spender, kind, amount, policy.maxAmount);
        }
    }

    function _validateIncreaseAllowanceFinalState(address safe, address token, address spender) internal view {
        if (!_approvalPolicyExists[token][spender][APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE]) {
            revert SafeTxShapeApprovalSpenderNotAllowed(token, spender, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE);
        }

        PhEvm.TriggerContext memory triggerCtx = ph.context();
        PhEvm.ForkId memory postFork = _postCall(triggerCtx.callEnd);

        PhEvm.StaticCallResult memory result = ph.staticcallAt(
            token, abi.encodeWithSignature("allowance(address,address)", safe, spender), ALLOWANCE_READ_GAS, postFork
        );
        if (!result.ok || result.data.length < 32) {
            revert SafeTxShapeAllowanceReadFailed(token, spender);
        }

        uint256 finalAllowance = abi.decode(result.data, (uint256));
        ApprovalPolicy storage policy = _approvalPolicyByKey[token][spender][APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE];

        if (finalAllowance == type(uint256).max) {
            if (!policy.allowUnlimited) {
                revert SafeTxShapeApprovalUnlimitedBlocked(token, spender, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE);
            }
            return;
        }
        if (finalAllowance > policy.maxAmount) {
            revert SafeTxShapeApprovalAmountAboveCap(
                token, spender, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE, finalAllowance, policy.maxAmount
            );
        }
    }

    function _validateOperatorApproval(address token, address operator, uint8 kind) internal view {
        if (!_operatorApprovalAllowed(token, operator, kind)) {
            revert SafeTxShapeApprovalSpenderNotAllowed(token, operator, kind);
        }
    }

    function _operatorApprovalAllowed(address token, address operator, uint8 kind) internal view returns (bool) {
        if (operator == address(0)) return false;
        return _approvalPolicyExists[token][operator][kind];
    }

    function _validateModuleCaller(address module) internal view {
        if (!moduleExecutionEnabled) revert SafeTxShapeModuleExecutionDisabled(module);
        if (!_allowedModule[module]) revert SafeTxShapeModuleNotAllowed(module);
    }

    function _resolveTriggeredSafeCall() internal view returns (TriggeredSafeCall memory triggered) {
        address safe = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory context = ph.context();

        if (context.selector == EXEC_TRANSACTION_SELECTOR) {
            return TriggeredSafeCall({
                selector: context.selector,
                caller: address(0),
                input: ph.callinputAt(context.callStart),
                callStart: context.callStart,
                callEnd: context.callEnd
            });
        }

        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(safe, context.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == context.callStart) {
                return TriggeredSafeCall({
                    selector: context.selector,
                    caller: calls[i].caller,
                    input: ph.callinputAt(context.callStart),
                    callStart: context.callStart,
                    callEnd: context.callEnd
                });
            }
        }

        revert SafeTxShapeTriggeredCallNotFound(context.selector, context.callStart);
    }

    function _decodeOwnerTx(bytes memory input) internal pure returns (OwnerTx memory ownerTx) {
        if (input.length < 388 || _selector(input) != EXEC_TRANSACTION_SELECTOR) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        ownerTx.to = _readAbiAddress(input, 4);
        ownerTx.value = _readUint256(input, 36);
        ownerTx.data = _readDynamicBytes(input, 4, _readUint256(input, 68));
        ownerTx.operation = _readAbiUint8(input, 100);
    }

    function _decodeModuleTx(bytes memory input) internal pure returns (ModuleTx memory moduleTx) {
        if (
            input.length < 164
                || (_selector(input) != EXEC_TRANSACTION_FROM_MODULE_SELECTOR
                    && _selector(input) != EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR)
        ) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        moduleTx.to = _readAbiAddress(input, 4);
        moduleTx.value = _readUint256(input, 36);
        moduleTx.data = _readDynamicBytes(input, 4, _readUint256(input, 68));
        moduleTx.operation = _readAbiUint8(input, 100);
    }

    function _decodeOwnerAction(address safe, bytes memory input) internal pure returns (Action memory action) {
        if (input.length < 388 || _selector(input) != EXEC_TRANSACTION_SELECTOR) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        (uint256 dataOffset, uint256 dataLength) = _dynamicBytesBounds(input, 4, _readUint256(input, 68));
        action = Action({
            safe: safe,
            module: address(0),
            target: _readAbiAddress(input, 4),
            value: _readUint256(input, 36),
            data: input,
            dataOffset: dataOffset,
            dataLength: dataLength,
            operation: _readAbiUint8(input, 100),
            fromModule: false,
            fromBatch: false
        });
    }

    function _decodeModuleAction(address safe, address module, bytes memory input)
        internal
        pure
        returns (Action memory action)
    {
        if (
            input.length < 164
                || (_selector(input) != EXEC_TRANSACTION_FROM_MODULE_SELECTOR
                    && _selector(input) != EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR)
        ) {
            revert SafeTxShapeBatchPayloadMalformed();
        }

        (uint256 dataOffset, uint256 dataLength) = _dynamicBytesBounds(input, 4, _readUint256(input, 68));
        action = Action({
            safe: safe,
            module: module,
            target: _readAbiAddress(input, 4),
            value: _readUint256(input, 36),
            data: input,
            dataOffset: dataOffset,
            dataLength: dataLength,
            operation: _readAbiUint8(input, 100),
            fromModule: true,
            fromBatch: false
        });
    }

    function _decodeSingleBytesArgument(
        bytes memory input,
        uint256 inputOffset,
        uint256 inputLength,
        bytes4 expectedSelector
    ) internal pure returns (uint256 argumentOffset, uint256 argumentLength) {
        if (inputOffset > input.length || inputLength > input.length - inputOffset || inputLength < 68) {
            revert SafeTxShapeBatchPayloadMalformed();
        }
        if (_selectorAt(input, inputOffset) != expectedSelector) revert SafeTxShapeBatchPayloadMalformed();

        uint256 offset = _readUint256(input, inputOffset + 4);
        if (offset != 32) revert SafeTxShapeBatchPayloadMalformed();

        uint256 inputEnd = inputOffset + inputLength;
        uint256 lengthOffset = inputOffset + 4 + offset;
        argumentLength = _readUint256(input, lengthOffset);
        argumentOffset = lengthOffset + 32;
        if (argumentOffset > inputEnd) revert SafeTxShapeBatchPayloadMalformed();
        if (argumentLength > inputEnd - argumentOffset) revert SafeTxShapeBatchPayloadMalformed();

        uint256 paddedLength = argumentLength;
        uint256 remainder = argumentLength % 32;
        if (remainder != 0) paddedLength += 32 - remainder;

        uint256 paddedEnd = argumentOffset + paddedLength;
        if (paddedEnd != inputEnd) revert SafeTxShapeBatchPayloadMalformed();
        for (uint256 i = argumentLength; i < paddedLength; ++i) {
            if (input[argumentOffset + i] != 0) revert SafeTxShapeBatchPayloadMalformed();
        }
    }

    function _batchPolicyForAction(address target, bytes memory data, uint256 dataOffset, uint256 dataLength)
        internal
        view
        returns (bool found, uint256 index)
    {
        if (dataLength < 4) return (false, 0);
        return _batchPolicyIndex(target, _selectorAt(data, dataOffset));
    }

    function _isConfiguredBatchCall(address target, bytes memory data, uint256 dataOffset, uint256 dataLength)
        internal
        view
        returns (bool)
    {
        if (dataLength < 4) return false;
        (bool found,) = _batchPolicyIndex(target, _selectorAt(data, dataOffset));
        return found;
    }

    function _targetPolicyIndex(address target) internal view returns (bool found, uint256 index) {
        uint256 indexPlusOne = _targetPolicyIndexPlusOne[target];
        if (indexPlusOne == 0) return (false, 0);
        return (true, indexPlusOne - 1);
    }

    function _selectorPolicyIndex(address target, bytes4 selector) internal view returns (bool found, uint256 index) {
        uint256 indexPlusOne = _selectorPolicyIndexPlusOne[target][selector];
        if (indexPlusOne == 0) return (false, 0);
        return (true, indexPlusOne - 1);
    }

    function _batchPolicyIndex(address executor, bytes4 selector) internal view returns (bool found, uint256 index) {
        uint256 indexPlusOne = _batchPolicyIndexPlusOne[executor][selector];
        if (indexPlusOne == 0) return (false, 0);
        return (true, indexPlusOne - 1);
    }

    function _tokenHasApprovalKind(address token, uint8 kind) internal view returns (bool) {
        return _tokenApprovalKindRegistered[token][kind];
    }

    function _storeTargetPolicies(TargetPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (policies[i].target == address(0)) revert SafeTxShapeInvalidPolicy();
            if (_targetPolicyIndexPlusOne[policies[i].target] != 0) {
                revert SafeTxShapeDuplicateTarget(policies[i].target);
            }

            targetPolicies.push(policies[i]);
            _targetPolicyIndexPlusOne[policies[i].target] = targetPolicies.length;
        }
    }

    function _storeSelectorPolicies(SelectorPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (policies[i].target == address(0) || policies[i].selector == bytes4(0)) {
                revert SafeTxShapeInvalidPolicy();
            }
            if (!_targetPolicyExistsInMemory(policies[i].target)) revert SafeTxShapeInvalidPolicy();
            if (_selectorPolicyIndexPlusOne[policies[i].target][policies[i].selector] != 0) {
                revert SafeTxShapeDuplicateSelector(policies[i].target, policies[i].selector);
            }

            selectorPolicies.push(policies[i]);
            _selectorPolicyIndexPlusOne[policies[i].target][policies[i].selector] = selectorPolicies.length;
        }
    }

    function _storeBatchExecutorPolicies(BatchExecutorPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (
                policies[i].executor == address(0) || policies[i].selector == bytes4(0) || policies[i].maxActions == 0
                    || policies[i].allowNested
            ) {
                revert SafeTxShapeInvalidPolicy();
            }
            if (_batchPolicyIndexPlusOne[policies[i].executor][policies[i].selector] != 0) {
                revert SafeTxShapeDuplicateBatchExecutor(policies[i].executor, policies[i].selector);
            }

            batchExecutorPolicies.push(policies[i]);
            _batchPolicyIndexPlusOne[policies[i].executor][policies[i].selector] = batchExecutorPolicies.length;
        }
    }

    function _storeApprovalPolicies(ApprovalPolicy[] memory policies) private {
        for (uint256 i; i < policies.length; ++i) {
            if (
                policies[i].token == address(0) || policies[i].spender == address(0)
                    || !_isSupportedApprovalKind(policies[i].kind)
            ) {
                revert SafeTxShapeInvalidPolicy();
            }

            for (uint256 j; j < i; ++j) {
                if (
                    policies[j].token == policies[i].token && policies[j].spender == policies[i].spender
                        && policies[j].kind == policies[i].kind
                ) {
                    revert SafeTxShapeDuplicateApprovalPolicy(policies[i].token, policies[i].spender, policies[i].kind);
                }

                if (
                    policies[j].token == policies[i].token
                        && ((policies[j].kind == APPROVAL_KIND_ERC20_APPROVE
                                && policies[i].kind == APPROVAL_KIND_ERC721_APPROVE)
                            || (policies[j].kind == APPROVAL_KIND_ERC721_APPROVE
                                && policies[i].kind == APPROVAL_KIND_ERC20_APPROVE))
                ) {
                    revert SafeTxShapeInvalidPolicy();
                }
            }

            approvalPolicies.push(policies[i]);
            _approvalPolicyByKey[policies[i].token][policies[i].spender][policies[i].kind] = policies[i];
            _approvalPolicyExists[policies[i].token][policies[i].spender][policies[i].kind] = true;
            _tokenApprovalKindRegistered[policies[i].token][policies[i].kind] = true;
        }
    }

    function _storeAllowedModules(address[] memory modules) private {
        for (uint256 i; i < modules.length; ++i) {
            if (modules[i] == address(0)) revert SafeTxShapeInvalidPolicy();
            if (_allowedModule[modules[i]]) revert SafeTxShapeDuplicateModule(modules[i]);

            allowedModules.push(modules[i]);
            _allowedModule[modules[i]] = true;
        }
    }

    function _targetPolicyExistsInMemory(address target) private view returns (bool) {
        return _targetPolicyIndexPlusOne[target] != 0;
    }

    function _isSupportedApprovalKind(uint8 kind) private pure returns (bool) {
        return kind == APPROVAL_KIND_ERC20_APPROVE || kind == APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE
            || kind == APPROVAL_KIND_ERC721_APPROVE || kind == APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL
            || kind == APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL;
    }

    function _registerReshiramSpec() internal {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        if (input.length < 4) revert SafeTxShapeCalldataTooShort(address(0), input.length);
        args = _slice(input, 4, input.length - 4);
    }

    function _selector(bytes memory input) internal pure returns (bytes4 selector) {
        if (input.length < 4) revert SafeTxShapeCalldataTooShort(address(0), input.length);
        selector = _selectorAt(input, 0);
    }

    function _selectorAt(bytes memory input, uint256 offset) internal pure returns (bytes4 selector) {
        if (offset > input.length || input.length - offset < 4) {
            revert SafeTxShapeCalldataTooShort(address(0), input.length);
        }
        selector = bytes4(
            (uint32(uint8(input[offset])) << 24) | (uint32(uint8(input[offset + 1])) << 16)
                | (uint32(uint8(input[offset + 2])) << 8) | uint32(uint8(input[offset + 3]))
        );
    }

    function _readAbiAddress(bytes memory data, uint256 offset) internal pure returns (address value) {
        value = address(uint160(_readUint256(data, offset)));
    }

    function _readAbiUint8(bytes memory data, uint256 offset) internal pure returns (uint8 value) {
        uint256 raw = _readUint256(data, offset);
        if (raw > type(uint8).max) revert SafeTxShapeBatchPayloadMalformed();
        value = uint8(raw);
    }

    function _readAbiBool(bytes memory data, uint256 offset) internal pure returns (bool value) {
        uint256 raw = _readUint256(data, offset);
        if (raw > 1) revert SafeTxShapeApprovalMalformed(address(0), bytes4(0));
        value = raw == 1;
    }

    function _readDynamicBytes(bytes memory data, uint256 headStart, uint256 relativeOffset)
        internal
        pure
        returns (bytes memory value)
    {
        (uint256 valueOffset, uint256 valueLength) = _dynamicBytesBounds(data, headStart, relativeOffset);
        value = _slice(data, valueOffset, valueLength);
    }

    function _dynamicBytesBounds(bytes memory data, uint256 headStart, uint256 relativeOffset)
        internal
        pure
        returns (uint256 valueOffset, uint256 valueLength)
    {
        if (headStart > data.length || relativeOffset > data.length - headStart) {
            revert SafeTxShapeBatchPayloadMalformed();
        }
        uint256 lengthOffset = headStart + relativeOffset;
        valueLength = _readUint256(data, lengthOffset);
        valueOffset = lengthOffset + 32;
        if (valueOffset > data.length) revert SafeTxShapeBatchPayloadMalformed();
        if (valueLength > data.length - valueOffset) revert SafeTxShapeBatchPayloadMalformed();
    }

    function _readPackedAddress(bytes memory data, uint256 offset) internal pure returns (address value) {
        if (offset > data.length || data.length - offset < 20) revert SafeTxShapeBatchPayloadMalformed();
        uint160 result;
        for (uint256 i; i < 20; ++i) {
            result = (result << 8) | uint160(uint8(data[offset + i]));
        }
        value = address(result);
    }

    function _readUint256(bytes memory data, uint256 offset) internal pure returns (uint256 value) {
        if (offset > data.length || data.length - offset < 32) revert SafeTxShapeBatchPayloadMalformed();
        for (uint256 i; i < 32; ++i) {
            value = (value << 8) | uint256(uint8(data[offset + i]));
        }
    }

    function _slice(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes memory out) {
        if (offset > data.length || length > data.length - offset) revert SafeTxShapeBatchPayloadMalformed();
        out = new bytes(length);
        for (uint256 i; i < length; ++i) {
            out[i] = data[offset + i];
        }
    }
}
