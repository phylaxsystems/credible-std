// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {IPerpetualProtectionSuite} from "./IPerpetualProtectionSuite.sol";

/// @title PerpetualBaseAssertion
/// @author Phylax Systems
/// @notice Generic operation-safety assertion for perpetual protocols.
/// @dev Inherit this together with a concrete `IPerpetualProtectionSuite` implementation. The base
///      contract handles one decode pass per triggered call, then enforces any suite-provided
///      execution, oracle, funding, liquidity, and liquidation checks before applying the shared
///      post-mutation risk gate for non-liquidation operations.
abstract contract PerpetualBaseAssertion is Assertion {
    error PerpetualTriggeredCallNotFound(bytes4 selector, uint256 callStart);
    error PerpetualOperationAccountMissing(bytes4 selector);
    error PerpetualExecutionPriceViolated(
        address account,
        bytes4 selector,
        IPerpetualProtectionSuite.OperationKind kind,
        bytes32 checkName,
        address market,
        uint256 executionPrice,
        uint256 minExecutionPrice,
        uint256 maxExecutionPrice
    );
    error PerpetualLiquidityCoverageViolated(
        bytes4 selector,
        IPerpetualProtectionSuite.OperationKind kind,
        bytes32 checkName,
        address market,
        uint256 requiredAmount,
        uint256 availableAmount
    );
    error PerpetualFundingDeltaViolated(
        address account,
        bytes4 selector,
        IPerpetualProtectionSuite.OperationKind kind,
        bytes32 checkName,
        address market,
        int256 actualFunding,
        int256 minExpectedFunding,
        int256 maxExpectedFunding
    );
    error PerpetualLiquidationViolated(
        address account,
        bytes4 selector,
        bytes32 checkName,
        address market,
        bool wasLiquidatableBefore,
        int256 lossCreated,
        uint256 absorbedLoss
    );
    error PerpetualOracleAnchorViolated(
        bytes4 selector,
        IPerpetualProtectionSuite.OperationKind kind,
        bytes32 checkName,
        address market,
        uint256 usedPrice,
        uint256 minOraclePrice,
        uint256 maxOraclePrice
    );
    error PerpetualSelfBadDebtCreated(
        address account, bytes4 selector, IPerpetualProtectionSuite.OperationKind kind, int256 equity
    );
    error PerpetualPostMutationRiskViolated(
        address account,
        bytes4 selector,
        IPerpetualProtectionSuite.OperationKind kind,
        bytes32 metricName,
        int256 metricValue,
        int256 thresholdValue
    );

    /// @notice Returns the protocol-specific perpetual suite that powers this assertion.
    function _suite() internal view virtual returns (IPerpetualProtectionSuite);

    /// @notice Registers one generic perpetual operation-safety check for every monitored selector.
    function triggers() external view virtual override {
        bytes4[] memory selectors = _suite().getMonitoredSelectors();
        for (uint256 i; i < selectors.length; ++i) {
            registerFnCallTrigger(this.assertOperationSafety.selector, selectors[i]);
        }
    }

    /// @notice Enforces the shared perpetual operation-safety invariants for a successful call.
    function assertOperationSafety() external view {
        _assertOperationSafety();
    }

    /// @notice Backwards-compatible alias for integrations that only reference the risk-gate name.
    function assertPostMutationRisk() external view {
        _assertOperationSafety();
    }

    /// @notice Internal implementation shared by the public perpetual assertion entrypoints.
    function _assertOperationSafety() internal view {
        IPerpetualProtectionSuite suite = _suite();
        IPerpetualProtectionSuite.TriggeredCall memory triggered = _resolveTriggeredCall();
        IPerpetualProtectionSuite.OperationContext memory operation = suite.decodeOperation(triggered);
        PhEvm.ForkId memory beforeFork = _preCall(triggered.callStart);
        PhEvm.ForkId memory afterFork = _postCall(triggered.callEnd);

        _assertExecutionPriceChecks(suite, triggered, operation, beforeFork, afterFork);
        _assertLiquidityCoverageChecks(suite, triggered, operation, beforeFork, afterFork);
        _assertFundingDeltaChecks(suite, triggered, operation, beforeFork, afterFork);
        _assertLiquidationChecks(suite, triggered, operation, beforeFork, afterFork);
        _assertOracleAnchorChecks(suite, triggered, operation, beforeFork, afterFork);
        _assertPostMutationRisk(suite, triggered, operation, afterFork);
    }

    /// @notice Enforces suite-provided taker execution bounds for the triggered operation.
    function _assertExecutionPriceChecks(
        IPerpetualProtectionSuite suite,
        IPerpetualProtectionSuite.TriggeredCall memory triggered,
        IPerpetualProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        IPerpetualProtectionSuite.ExecutionPriceCheck[] memory checks =
            suite.getExecutionPriceChecks(triggered, operation, beforeFork, afterFork);

        for (uint256 i; i < checks.length; ++i) {
            if (!_isWithinUintRange(checks[i].executionPrice, checks[i].minExecutionPrice, checks[i].maxExecutionPrice))
            {
                revert PerpetualExecutionPriceViolated(
                    checks[i].account == address(0) ? operation.account : checks[i].account,
                    operation.selector,
                    operation.kind,
                    checks[i].checkName,
                    checks[i].market,
                    checks[i].executionPrice,
                    checks[i].minExecutionPrice,
                    checks[i].maxExecutionPrice
                );
            }
        }
    }

    /// @notice Enforces suite-provided liquidity and liability coverage bounds.
    function _assertLiquidityCoverageChecks(
        IPerpetualProtectionSuite suite,
        IPerpetualProtectionSuite.TriggeredCall memory triggered,
        IPerpetualProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        IPerpetualProtectionSuite.LiquidityCoverageCheck[] memory checks =
            suite.getLiquidityCoverageChecks(triggered, operation, beforeFork, afterFork);

        for (uint256 i; i < checks.length; ++i) {
            if (checks[i].requiredAmount > checks[i].availableAmount) {
                revert PerpetualLiquidityCoverageViolated(
                    operation.selector,
                    operation.kind,
                    checks[i].checkName,
                    checks[i].market,
                    checks[i].requiredAmount,
                    checks[i].availableAmount
                );
            }
        }
    }

    /// @notice Enforces suite-provided cumulative-funding settlement bounds.
    function _assertFundingDeltaChecks(
        IPerpetualProtectionSuite suite,
        IPerpetualProtectionSuite.TriggeredCall memory triggered,
        IPerpetualProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        IPerpetualProtectionSuite.FundingDeltaCheck[] memory checks =
            suite.getFundingDeltaChecks(triggered, operation, beforeFork, afterFork);

        for (uint256 i; i < checks.length; ++i) {
            if (!_isWithinIntRange(checks[i].actualFunding, checks[i].minExpectedFunding, checks[i].maxExpectedFunding))
            {
                revert PerpetualFundingDeltaViolated(
                    checks[i].account == address(0) ? operation.account : checks[i].account,
                    operation.selector,
                    operation.kind,
                    checks[i].checkName,
                    checks[i].market,
                    checks[i].actualFunding,
                    checks[i].minExpectedFunding,
                    checks[i].maxExpectedFunding
                );
            }
        }
    }

    /// @notice Enforces suite-provided liquidation gating and loss-accounting bounds.
    function _assertLiquidationChecks(
        IPerpetualProtectionSuite suite,
        IPerpetualProtectionSuite.TriggeredCall memory triggered,
        IPerpetualProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        IPerpetualProtectionSuite.LiquidationCheck[] memory checks =
            suite.getLiquidationChecks(triggered, operation, beforeFork, afterFork);

        for (uint256 i; i < checks.length; ++i) {
            uint256 requiredAbsorption = _positivePart(checks[i].lossCreated);
            if (
                !checks[i].wasLiquidatableBefore || requiredAbsorption > checks[i].absorbedLoss
                    || (requiredAbsorption != 0 && checks[i].absorber == address(0))
            ) {
                revert PerpetualLiquidationViolated(
                    checks[i].account == address(0) ? operation.account : checks[i].account,
                    operation.selector,
                    checks[i].checkName,
                    checks[i].market,
                    checks[i].wasLiquidatableBefore,
                    checks[i].lossCreated,
                    checks[i].absorbedLoss
                );
            }
        }
    }

    /// @notice Enforces suite-provided oracle-anchor bounds for risk-critical transitions.
    function _assertOracleAnchorChecks(
        IPerpetualProtectionSuite suite,
        IPerpetualProtectionSuite.TriggeredCall memory triggered,
        IPerpetualProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        IPerpetualProtectionSuite.OracleAnchorCheck[] memory checks =
            suite.getOracleAnchorChecks(triggered, operation, beforeFork, afterFork);

        for (uint256 i; i < checks.length; ++i) {
            if (!_isWithinUintRange(checks[i].usedPrice, checks[i].minOraclePrice, checks[i].maxOraclePrice)) {
                revert PerpetualOracleAnchorViolated(
                    operation.selector,
                    operation.kind,
                    checks[i].checkName,
                    checks[i].market,
                    checks[i].usedPrice,
                    checks[i].minOraclePrice,
                    checks[i].maxOraclePrice
                );
            }
        }
    }

    /// @notice Enforces the shared post-mutation risk gate for non-liquidation operations.
    function _assertPostMutationRisk(
        IPerpetualProtectionSuite suite,
        IPerpetualProtectionSuite.TriggeredCall memory triggered,
        IPerpetualProtectionSuite.OperationContext memory operation,
        PhEvm.ForkId memory afterFork
    ) internal view {
        if (!suite.shouldCheckPostMutationRisk(operation)) {
            return;
        }

        if (operation.account == address(0)) {
            revert PerpetualOperationAccountMissing(triggered.selector);
        }

        IPerpetualProtectionSuite.AccountSnapshot memory snapshot =
            suite.getPostMutationSnapshot(triggered, operation, afterFork);

        if (snapshot.risk.hasBadDebt || snapshot.risk.equity < 0) {
            revert PerpetualSelfBadDebtCreated(
                operation.account, operation.selector, operation.kind, snapshot.risk.equity
            );
        }

        if (!snapshot.risk.isHealthy) {
            revert PerpetualPostMutationRiskViolated(
                operation.account,
                operation.selector,
                operation.kind,
                snapshot.risk.metricName,
                snapshot.risk.metricValue,
                snapshot.risk.thresholdValue
            );
        }
    }

    /// @notice Resolves the exact adopter frame that caused the current assertion execution.
    function _resolveTriggeredCall() internal view returns (IPerpetualProtectionSuite.TriggeredCall memory triggered) {
        address adopter = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory context = ph.context();
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(adopter, context.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == context.callStart) {
                return IPerpetualProtectionSuite.TriggeredCall({
                    selector: context.selector,
                    caller: calls[i].caller,
                    target: calls[i].target_address,
                    input: calls[i].input,
                    callStart: context.callStart,
                    callEnd: context.callEnd
                });
            }
        }

        revert PerpetualTriggeredCallNotFound(context.selector, context.callStart);
    }

    /// @notice Returns whether `value` lies within the inclusive `[minimum, maximum]` range.
    function _isWithinUintRange(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (bool) {
        return value >= minimum && value <= maximum;
    }

    /// @notice Returns whether `value` lies within the inclusive `[minimum, maximum]` range.
    function _isWithinIntRange(int256 value, int256 minimum, int256 maximum) internal pure returns (bool) {
        return value >= minimum && value <= maximum;
    }

    /// @notice Returns the non-negative component of a signed deficit.
    function _positivePart(int256 value) internal pure returns (uint256) {
        if (value <= 0) {
            return 0;
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(value);
    }
}
