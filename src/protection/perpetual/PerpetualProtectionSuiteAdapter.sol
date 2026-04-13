// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {IPerpetualProtectionSuite} from "./IPerpetualProtectionSuite.sol";

/// @title PerpetualProtectionSuiteAdapter
/// @author Phylax Systems
/// @notice Default snapshot composer for step-oriented perpetual suites.
/// @dev Implementations can inherit this and only override `getAccountSnapshot(...)` when they
///      need a protocol-specific hot path or can answer the invariant more cheaply.
abstract contract PerpetualProtectionSuiteAdapter is IPerpetualProtectionSuite {
    /// @notice Default execution-price implementation for suites with no shared execution check.
    function getExecutionPriceChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view virtual override returns (ExecutionPriceCheck[] memory checks) {
        triggered;
        operation;
        beforeFork;
        afterFork;
        checks = new ExecutionPriceCheck[](0);
    }

    /// @notice Default liquidity-coverage implementation for suites with no shared coverage check.
    function getLiquidityCoverageChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view virtual override returns (LiquidityCoverageCheck[] memory checks) {
        triggered;
        operation;
        beforeFork;
        afterFork;
        checks = new LiquidityCoverageCheck[](0);
    }

    /// @notice Default funding-delta implementation for suites with no shared funding check.
    function getFundingDeltaChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view virtual override returns (FundingDeltaCheck[] memory checks) {
        triggered;
        operation;
        beforeFork;
        afterFork;
        checks = new FundingDeltaCheck[](0);
    }

    /// @notice Default liquidation implementation for suites with no shared liquidation checks.
    function getLiquidationChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view virtual override returns (LiquidationCheck[] memory checks) {
        triggered;
        operation;
        beforeFork;
        afterFork;
        checks = new LiquidationCheck[](0);
    }

    /// @notice Default oracle-anchor implementation for suites with no shared oracle check.
    function getOracleAnchorChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view virtual override returns (OracleAnchorCheck[] memory checks) {
        triggered;
        operation;
        beforeFork;
        afterFork;
        checks = new OracleAnchorCheck[](0);
    }

    /// @notice Default post-mutation snapshot implementation for suites with account-only risk reads.
    function getPostMutationSnapshot(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata fork
    ) external view virtual override returns (AccountSnapshot memory snapshot) {
        triggered;
        snapshot = this.getAccountSnapshot(operation.account, fork);
    }

    /// @notice Composes a full account snapshot from the step-oriented suite functions.
    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        virtual
        override
        returns (AccountSnapshot memory snapshot)
    {
        snapshot.state = this.getAccountState(account, fork);
        snapshot.positions = this.getAccountPositions(account, fork);
        snapshot.risk = this.evaluateRisk(snapshot.state, snapshot.positions, fork);
    }
}
