// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {AssertionSpec} from "../../SpecRecorder.sol";
import {ForkUtils} from "../../utils/ForkUtils.sol";
import {ILendingProtectionSuite} from "./ILendingProtectionSuite.sol";

/// @title LendingProtectionSuiteBase
/// @author Phylax Systems
/// @notice Shared default implementations for lending protection suites.
abstract contract LendingProtectionSuiteBase is ForkUtils, ILendingProtectionSuite {
    /// @notice Default bounded-consumption implementation for suites with no extra resource checks.
    /// @dev Override this when the protocol needs withdraw, liquidation, or other consumption bounds.
    ///      Returning an empty array keeps solvency-only suites source-compatible with the generic
    ///      lending assertion.
    /// @param triggered The exact adopter frame that caused the assertion to run.
    /// @param operation The decoded operation context.
    /// @param beforeFork The pre-call snapshot fork.
    /// @param afterFork The post-call snapshot fork.
    /// @return checks Empty by default.
    function getConsumptionChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view virtual override returns (ConsumptionCheck[] memory checks) {
        triggered;
        operation;
        beforeFork;
        afterFork;
        checks = new ConsumptionCheck[](0);
    }

    /// @notice Composes a full account snapshot from the step-oriented suite functions.
    /// @dev This is the default implementation for step-based suites. Override it only when the
    ///      protocol exposes a materially cheaper or more direct way to answer the invariant than
    ///      calling `getAccountState(...)`, `getAccountBalances(...)`, and `evaluateSolvency(...)`
    ///      separately.
    /// @param account The account whose post-operation state should be read.
    /// @param fork The snapshot fork to query.
    /// @return snapshot Aggregate state, balances, and solvency produced by the suite steps.
    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        virtual
        override
        returns (AccountSnapshot memory snapshot)
    {
        snapshot.state = this.getAccountState(account, fork);
        snapshot.balances = this.getAccountBalances(account, fork);
        snapshot.solvency = this.evaluateSolvency(snapshot.state, snapshot.balances, fork);
    }

    /// @notice Returns the suite-specific revert string for failed fork-time static calls.
    function _viewFailureMessage() internal pure virtual override returns (string memory) {
        return "lending suite staticcall failed";
    }
}

/// @title LendingBaseAssertion
/// @author Phylax Systems
/// @notice Generic lending operation-safety assertion for lending protocols.
/// @dev Inherit this together with a concrete `ILendingProtectionSuite` implementation. The base
///      contract handles one decode pass per triggered call, then enforces both:
///      - any bounded-consumption checks returned by the suite
///      - post-operation solvency for risk-increasing operations
abstract contract LendingBaseAssertion is Assertion {
    error LendingTriggeredCallNotFound(bytes4 selector, uint256 callStart);
    error LendingOperationAccountMissing(bytes4 selector);
    error LendingConsumptionCheckViolated(
        address account,
        bytes4 selector,
        ILendingProtectionSuite.OperationKind kind,
        bytes32 checkName,
        address asset,
        uint256 consumed,
        uint256 availableBefore
    );
    error LendingPostOperationSolvencyViolated(
        address account,
        bytes4 selector,
        ILendingProtectionSuite.OperationKind kind,
        bytes32 metricName,
        int256 metric,
        int256 threshold
    );

    /// @notice Returns the protocol-specific lending suite that powers this assertion.
    /// @dev Concrete assertions typically inherit both this base contract and a suite contract, then
    ///      return `ILendingProtectionSuite(address(this))`. Returning a different contract is also
    ///      valid if the assertion delegates protocol logic elsewhere.
    /// @return suite The suite used to decode operations and evaluate solvency.
    function _suite() internal view virtual returns (ILendingProtectionSuite);

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers one generic lending operation-safety check for every monitored selector.
    /// @dev This is the only trigger wiring most lending assertions need to implement. The suite
    ///      decides which selectors matter through `getMonitoredSelectors()`, and this base maps all
    ///      of them to `assertOperationSafety()`.
    function triggers() external view virtual override {
        bytes4[] memory selectors = _suite().getMonitoredSelectors();
        for (uint256 i; i < selectors.length; ++i) {
            registerFnCallTrigger(this.assertOperationSafety.selector, selectors[i]);
        }
    }

    /// @notice Enforces the shared lending operation-safety invariants for a successful call.
    /// @dev Assertion authors should usually point Credible at this selector. The method resolves the
    ///      triggering adopter frame, decodes the protocol operation once, enforces any bounded-
    ///      consumption checks returned by the suite, and then enforces post-operation solvency when
    ///      the suite marks the operation as risk-increasing.
    function assertOperationSafety() external view {
        _assertOperationSafety();
    }

    /// @notice Backwards-compatible alias for the legacy solvency-only entrypoint name.
    /// @dev Older bundles may still reference this selector directly. It now runs the full generic
    ///      lending operation-safety pipeline rather than only the solvency portion.
    function assertPostOperationSolvency() external view {
        _assertOperationSafety();
    }

    /// @notice Internal implementation shared by the public lending assertion entrypoints.
    /// @dev Runs all shared lending checks exposed by the suite against the triggered adopter call.
    function _assertOperationSafety() internal view {
        ILendingProtectionSuite suite = _suite();
        ILendingProtectionSuite.TriggeredCall memory triggered = _resolveTriggeredCall();
        ILendingProtectionSuite.OperationContext memory operation = suite.decodeOperation(triggered);
        PhEvm.ForkId memory beforeFork = _preCall(triggered.callStart);
        PhEvm.ForkId memory afterFork = _postCall(triggered.callEnd);

        _assertConsumptionChecks(suite, triggered, operation, beforeFork, afterFork);
        _assertPostOperationSolvency(suite, triggered, operation, afterFork);
    }

    /// @notice Enforces the suite-provided bounded-consumption checks for the triggered operation.
    /// @dev Suites may return zero, one, or many bounds depending on the operation kind. Each bound
    ///      is enforced as `consumed <= availableBefore`, where both values must already be expressed
    ///      in the same protocol-defined units.
    /// @param suite The protocol-specific lending suite.
    /// @param triggered The exact adopter frame that caused the assertion to run.
    /// @param operation The decoded lending operation.
    /// @param beforeFork The pre-call snapshot fork.
    /// @param afterFork The post-call snapshot fork.
    function _assertConsumptionChecks(
        ILendingProtectionSuite suite,
        ILendingProtectionSuite.TriggeredCall memory triggered,
        ILendingProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        ILendingProtectionSuite.ConsumptionCheck[] memory checks =
            suite.getConsumptionChecks(triggered, operation, beforeFork, afterFork);

        for (uint256 i; i < checks.length; ++i) {
            if (checks[i].consumed > checks[i].availableBefore) {
                revert LendingConsumptionCheckViolated(
                    checks[i].account == address(0) ? operation.account : checks[i].account,
                    operation.selector,
                    operation.kind,
                    checks[i].checkName,
                    checks[i].asset,
                    checks[i].consumed,
                    checks[i].availableBefore
                );
            }
        }
    }

    /// @notice Enforces post-operation solvency for risk-increasing operations.
    /// @dev Operations that do not increase debt or reduce effective collateral are skipped. This is
    ///      the original shared lending invariant, now run as one stage of the broader
    ///      operation-safety pipeline.
    /// @param suite The protocol-specific lending suite.
    /// @param triggered The exact adopter frame that caused the assertion to run.
    /// @param operation The decoded lending operation.
    /// @param afterFork The post-call snapshot fork used for the solvency read.
    function _assertPostOperationSolvency(
        ILendingProtectionSuite suite,
        ILendingProtectionSuite.TriggeredCall memory triggered,
        ILendingProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory afterFork
    ) internal view {
        // bug: false positive on partial liquidation or adding new cross collateral reserve asset or e mode switch if undercolalteralized
        if (!suite.shouldCheckPostOperationSolvency(operation)) {
            return;
        }

        if (operation.account == address(0)) {
            revert LendingOperationAccountMissing(triggered.selector);
        }

        ILendingProtectionSuite.AccountSnapshot memory snapshot = suite.getAccountSnapshot(operation.account, afterFork);

        if (!snapshot.solvency.isSolvent) {
            revert LendingPostOperationSolvencyViolated(
                operation.account,
                operation.selector,
                operation.kind,
                snapshot.solvency.metricName,
                snapshot.solvency.metric,
                snapshot.solvency.threshold
            );
        }
    }

    /// @notice Resolves the exact adopter frame that caused the current assertion execution.
    /// @dev Credible exposes the selector and call identifiers in `ph.context()`, but the suite also
    ///      needs raw calldata and caller information for correct protocol decoding. This helper
    ///      reconstructs that frame from `getAllCallInputs(...)` and packages it into
    ///      `ILendingProtectionSuite.TriggeredCall`.
    /// @return triggered Caller-aware information about the adopter call being checked.
    function _resolveTriggeredCall() internal view returns (ILendingProtectionSuite.TriggeredCall memory triggered) {
        address adopter = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory context = ph.context();
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(adopter, context.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == context.callStart) {
                return ILendingProtectionSuite.TriggeredCall({
                    selector: context.selector,
                    caller: calls[i].caller,
                    target: calls[i].target_address,
                    input: calls[i].input,
                    callStart: context.callStart,
                    callEnd: context.callEnd
                });
            }
        }

        revert LendingTriggeredCallNotFound(context.selector, context.callStart);
    }
}
