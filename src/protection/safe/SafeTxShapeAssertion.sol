// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {SafeTxShapeHelpers} from "./SafeTxShapeHelpers.sol";

/// @title SafeTxShapeAssertion
/// @author Phylax Systems
/// @notice Enforces direct Safe action-shape policy for owner and module executions.
/// @dev Validates the Safe transaction tuple before settlement: known targets, exact
///      selectors, delegatecall restrictions, approved MultiSend batch contents, and
///      token approval spender/operator policy.
contract SafeTxShapeAssertion is SafeTxShapeHelpers {
    constructor(
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
    {}

    function triggers() external view override {
        registerFnCallTrigger(this.assertSafeModulePolicy.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertSafeModulePolicy.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(this.assertSafeModulePolicy.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR);

        registerFnCallTrigger(this.assertSafeDelegateCallPolicy.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertSafeDelegateCallPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(
            this.assertSafeDelegateCallPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR
        );

        registerFnCallTrigger(this.assertSafeTargetSelectorPolicy.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertSafeTargetSelectorPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(
            this.assertSafeTargetSelectorPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR
        );

        registerFnCallTrigger(this.assertSafeBatchPolicy.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertSafeBatchPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(this.assertSafeBatchPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR);

        registerFnCallTrigger(this.assertSafeApprovalPolicy.selector, EXEC_TRANSACTION_SELECTOR);
        registerFnCallTrigger(this.assertSafeApprovalPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_SELECTOR);
        registerFnCallTrigger(this.assertSafeApprovalPolicy.selector, EXEC_TRANSACTION_FROM_MODULE_RETURN_DATA_SELECTOR);
    }

    /// @notice Ensures module executions are disabled or sent by an allowlisted module.
    function assertSafeModulePolicy() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        if (ctx.selector == EXEC_TRANSACTION_SELECTOR) {
            _requireNoOwnerGasRefund(ph.callinputAt(ctx.callStart));
            return;
        }

        Action memory action = _triggeredAction();
        if (action.fromModule) _validateModuleCaller(action.module);
    }

    /// @notice Blocks direct, module, and inner delegatecalls except configured top-level MultiSend execution.
    function assertSafeDelegateCallPolicy() external view {
        Action memory action = _triggeredAction();
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);

        (bool isBatchExecutor, uint256 batchIndex) =
            _batchPolicyForAction(action.target, action.data, action.dataOffset, action.dataLength);
        if (isBatchExecutor) {
            BatchExecutorPolicy storage batchPolicy = batchExecutorPolicies[batchIndex];
            if (action.operation == OPERATION_DELEGATECALL && !batchPolicy.allowDelegateCall) {
                revert SafeTxShapeBatchDelegateCallNotAllowed(action.target);
            }
            _validateMultiSendDelegateCallPolicy(action, batchPolicy);
            return;
        }

        if (action.operation == OPERATION_DELEGATECALL) revert SafeTxShapeDelegateCallBlocked(action.target);
    }

    /// @notice Ensures every non-batch action uses a known target and allowed selector.
    function assertSafeTargetSelectorPolicy() external view {
        Action memory action = _triggeredAction();
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);

        (bool isBatchExecutor, uint256 batchIndex) =
            _batchPolicyForAction(action.target, action.data, action.dataOffset, action.dataLength);
        if (isBatchExecutor) {
            _validateMultiSendTargetSelectorPolicy(action, batchExecutorPolicies[batchIndex]);
            return;
        }

        if (action.operation == OPERATION_DELEGATECALL) return;

        _validateTargetAndSelector(action);
    }

    /// @notice Strictly parses configured MultiSend batches and rejects malformed or nested batches.
    function assertSafeBatchPolicy() external view {
        Action memory action = _triggeredAction();
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);

        (bool isBatchExecutor, uint256 batchIndex) =
            _batchPolicyForAction(action.target, action.data, action.dataOffset, action.dataLength);
        if (!isBatchExecutor) return;

        BatchExecutorPolicy storage batchPolicy = batchExecutorPolicies[batchIndex];
        if (action.operation == OPERATION_DELEGATECALL && !batchPolicy.allowDelegateCall) {
            revert SafeTxShapeBatchDelegateCallNotAllowed(action.target);
        }
        _validateMultiSendBatchPolicy(action, batchPolicy);
    }

    /// @notice Enforces spender/operator and amount limits for approval-like calls.
    function assertSafeApprovalPolicy() external view {
        Action memory action = _triggeredAction();
        if (action.operation > OPERATION_DELEGATECALL) revert SafeTxShapeUnknownOperation(action.operation);

        (bool isBatchExecutor, uint256 batchIndex) =
            _batchPolicyForAction(action.target, action.data, action.dataOffset, action.dataLength);
        if (isBatchExecutor) {
            _validateMultiSendApprovalPolicy(action, batchExecutorPolicies[batchIndex]);
            return;
        }

        if (action.operation == OPERATION_DELEGATECALL) return;

        if (action.dataLength < 4) return;
        _validateApproval(action, _selectorAt(action.data, action.dataOffset));
    }
}
