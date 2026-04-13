// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {ILendingProtectionSuite} from "./ILendingProtectionSuite.sol";

/// @title LendingProtectionSuiteAdapter
/// @author Phylax Systems
/// @notice Default snapshot composer for step-oriented lending suites.
/// @dev Implementations can inherit this and only override `getAccountSnapshot(...)`
///      when they need a protocol-specific fast path.
abstract contract LendingProtectionSuiteAdapter is ILendingProtectionSuite {
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
}
