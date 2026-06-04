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

    /// @notice Default consumption-selector set: every monitored selector keeps a per-call check.
    /// @dev Override this in suites that only attach bounded-consumption checks to a subset of their
    ///      monitored selectors so the generic assertion can drop redundant per-call triggers. The
    ///      default preserves the historical behavior of running the per-call check on all monitored
    ///      selectors.
    /// @return selectors The selectors that must keep a per-call consumption trigger.
    function getConsumptionSelectors() external view virtual override returns (bytes4[] memory selectors) {
        return this.getMonitoredSelectors();
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
///      - healthy accounts are not made insolvent by risk-increasing operations
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
    error LendingAccountSolvencyViolated(address account, bytes32 metricName, int256 metric, int256 threshold);

    /// @notice Returns the protocol-specific lending suite that powers this assertion.
    /// @dev Concrete assertions typically inherit both this base contract and a suite contract, then
    ///      return `ILendingProtectionSuite(address(this))`. Returning a different contract is also
    ///      valid if the assertion delegates protocol logic elsewhere.
    /// @return suite The suite used to decode operations and evaluate solvency.
    function _suite() internal view virtual returns (ILendingProtectionSuite);

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the per-call consumption checks and the transaction-end solvency check.
    /// @dev Trigger strategy after optimization:
    ///      - Bounded-consumption checks genuinely need per-call context (traced call output, per-call
    ///        transfer deltas), so they stay on `registerFnCallTrigger`, scoped to the selectors that
    ///        actually carry a consumption check via `getConsumptionSelectors()`.
    ///      - Post-operation solvency is a transaction-wide property, so it runs once via
    ///        `registerTxEndTrigger` rather than on every risk-increasing call. The tx-end check
    ///        enumerates every monitored call in the transaction, dedupes the affected accounts, and
    ///        requires that any account solvent at the start of the transaction is still solvent at
    ///        the end.
    function triggers() external view virtual override {
        ILendingProtectionSuite suite = _suite();

        bytes4[] memory consumptionSelectors = suite.getConsumptionSelectors();
        for (uint256 i; i < consumptionSelectors.length; ++i) {
            registerFnCallTrigger(this.assertOperationSafety.selector, consumptionSelectors[i]);
        }

        registerTxEndTrigger(this.assertAccountSolvency.selector);
    }

    /// @notice Enforces the per-call bounded-consumption invariants for a successful call.
    /// @dev Resolves the triggering adopter frame, decodes the protocol operation once, and enforces
    ///      any bounded-consumption checks returned by the suite. Post-operation solvency is no longer
    ///      checked here; it is enforced once per transaction by `assertAccountSolvency()`.
    function assertOperationSafety() external view {
        _assertOperationConsumption();
    }

    /// @notice Enforces post-operation solvency across the whole transaction.
    /// @dev Fired by `registerTxEndTrigger`. Every account touched by a risk-increasing monitored call
    ///      that was solvent at PreTx must still be solvent at PostTx.
    function assertAccountSolvency() external view {
        _assertAccountSolvency();
    }

    /// @notice Backwards-compatible alias for the legacy solvency entrypoint name.
    /// @dev Older bundles may still reference this selector directly. It now runs the transaction-end
    ///      solvency check.
    function assertPostOperationSolvency() external view {
        _assertAccountSolvency();
    }

    /// @notice Per-call consumption pipeline shared by the public lending entrypoints.
    /// @dev Runs the suite's bounded-consumption checks against the triggered adopter call.
    function _assertOperationConsumption() internal view {
        ILendingProtectionSuite suite = _suite();
        ILendingProtectionSuite.TriggeredCall memory triggered = _resolveTriggeredCall();
        ILendingProtectionSuite.OperationContext memory operation = suite.decodeOperation(triggered);
        PhEvm.ForkId memory beforeFork = _preCall(triggered.callStart);
        PhEvm.ForkId memory afterFork = _postCall(triggered.callEnd);

        _assertConsumptionChecks(suite, triggered, operation, beforeFork, afterFork);
    }

    /// @notice Transaction-end solvency pipeline.
    /// @dev Enumerates every monitored call in the transaction via `getAllCallInputs`, decodes the
    ///      affected account for each risk-increasing call, dedupes accounts, and requires that any
    ///      account solvent at PreTx is still solvent at PostTx. Enumerating by adopter+selector means
    ///      router/proxy entrypoints that reach the pool are covered. Consumption checks deliberately
    ///      stay per-call; this method only enforces solvency.
    function _assertAccountSolvency() internal view {
        ILendingProtectionSuite suite = _suite();
        address adopter = ph.getAssertionAdopter();
        bytes4[] memory selectors = suite.getMonitoredSelectors();

        uint256 maxAccounts;
        for (uint256 i; i < selectors.length; ++i) {
            maxAccounts += ph.getAllCallInputs(adopter, selectors[i]).length;
        }

        address[] memory accounts = new address[](maxAccounts);
        uint256 count;

        for (uint256 i; i < selectors.length; ++i) {
            PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(adopter, selectors[i]);
            for (uint256 j; j < calls.length; ++j) {
                // `getAllCallInputs` returns calldata args WITHOUT the 4-byte selector (it is the
                // query key), but `decodeOperation` expects selector-prefixed calldata. Prepend it.
                ILendingProtectionSuite.OperationContext memory operation = suite.decodeOperation(
                    ILendingProtectionSuite.TriggeredCall({
                        selector: selectors[i],
                        caller: calls[j].caller,
                        target: calls[j].target_address,
                        input: bytes.concat(selectors[i], calls[j].input),
                        callStart: 0,
                        callEnd: 0
                    })
                );

                if (operation.account == address(0) || !suite.shouldCheckPostOperationSolvency(operation)) {
                    continue;
                }

                bool seen;
                for (uint256 k; k < count; ++k) {
                    if (accounts[k] == operation.account) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) {
                    accounts[count++] = operation.account;
                }
            }
        }

        if (count == 0) {
            return;
        }

        PhEvm.ForkId memory preTx = _preTx();
        PhEvm.ForkId memory postTx = _postTx();

        for (uint256 k; k < count; ++k) {
            address account = accounts[k];

            ILendingProtectionSuite.AccountSnapshot memory beforeSnapshot = suite.getAccountSnapshot(account, preTx);
            if (!beforeSnapshot.solvency.isSolvent) {
                continue;
            }

            ILendingProtectionSuite.AccountSnapshot memory afterSnapshot = suite.getAccountSnapshot(account, postTx);
            if (!afterSnapshot.solvency.isSolvent) {
                revert LendingAccountSolvencyViolated(
                    account,
                    afterSnapshot.solvency.metricName,
                    afterSnapshot.solvency.metric,
                    afterSnapshot.solvency.threshold
                );
            }
        }
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
                // `getAllCallInputs` returns calldata args WITHOUT the 4-byte selector (it is the
                // query key), but `decodeOperation` expects selector-prefixed calldata. Prepend it.
                return ILendingProtectionSuite.TriggeredCall({
                    selector: context.selector,
                    caller: calls[i].caller,
                    target: calls[i].target_address,
                    input: bytes.concat(context.selector, calls[i].input),
                    callStart: context.callStart,
                    callEnd: context.callEnd
                });
            }
        }

        revert LendingTriggeredCallNotFound(context.selector, context.callStart);
    }
}
