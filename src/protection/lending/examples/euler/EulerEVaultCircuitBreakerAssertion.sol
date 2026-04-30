// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";

import {EulerEVaultBase} from "./EulerEVaultHelpers.sol";
import {IEulerEVaultLike} from "./EulerEVaultInterfaces.sol";

/// @title EulerEVaultCircuitBreakerMixin
/// @author Phylax Systems
/// @notice Registers EVK asset-flow circuit breakers for the underlying asset.
/// @dev The policy is deliberately small:
///      - excessive inflow hard-blocks the transaction
///      - 10% cumulative outflow in 24h requires a successful liquidation
///      - 15% cumulative outflow in 24h hard-blocks the transaction
abstract contract EulerEVaultCircuitBreakerMixin is EulerEVaultBase {
    uint256 public constant LIQUIDATION_ONLY_OUTFLOW_THRESHOLD_BPS = 1_000;
    uint256 public constant FULL_PAUSE_OUTFLOW_THRESHOLD_BPS = 1_500;
    uint256 public constant OUTFLOW_PAUSE_WINDOW_DURATION = 24 hours;

    address public immutable flowAsset;
    uint256 public immutable inflowThresholdBps;
    uint256 public immutable inflowWindowDuration;

    constructor(address asset_, uint256 inflowThresholdBps_, uint256 inflowWindowDuration_) {
        flowAsset = asset_;
        inflowThresholdBps = inflowThresholdBps_;
        inflowWindowDuration = inflowWindowDuration_;
    }

    function _registerCircuitBreakers() internal view {
        watchCumulativeInflow(
            flowAsset, inflowThresholdBps, inflowWindowDuration, this.assertPauseAfterExcessiveInflow.selector
        );
        watchCumulativeOutflow(
            flowAsset,
            LIQUIDATION_ONLY_OUTFLOW_THRESHOLD_BPS,
            OUTFLOW_PAUSE_WINDOW_DURATION,
            this.assertLiquidationOnlyAfterLargeOutflow.selector
        );
        watchCumulativeOutflow(
            flowAsset,
            FULL_PAUSE_OUTFLOW_THRESHOLD_BPS,
            OUTFLOW_PAUSE_WINDOW_DURATION,
            this.assertPauseAfterCriticalOutflow.selector
        );
    }

    /// @notice Fully pauses the EVault when cumulative underlying inflow breaches the configured threshold.
    /// @dev This hard breaker reverts every transaction that still breaches the inflow window.
    function assertPauseAfterExcessiveInflow() external view {
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ctx.token == flowAsset, "EulerEVault: wrong inflow token context");

        revert("EulerEVault: excessive inflow pause");
    }

    /// @notice Enforces liquidation-only mode after 10% cumulative outflow in the rolling window.
    /// @dev A failure means the transaction breached the 10% outflow tier without a successful
    ///      liquidation call.
    function assertLiquidationOnlyAfterLargeOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == flowAsset, "EulerEVault: wrong outflow token context");

        require(
            _matchingCalls(_vault(), IEulerEVaultLike.liquidate.selector, 1).length != 0,
            "EulerEVault: liquidation required"
        );
    }

    /// @notice Fully pauses the EVault after 15% cumulative outflow in 24 hours.
    /// @dev This hard breaker reverts any transaction that still breaches the critical outflow tier.
    function assertPauseAfterCriticalOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == flowAsset, "EulerEVault: wrong critical outflow token");

        revert("EulerEVault: critical outflow pause");
    }
}

/// @title EulerEVaultCircuitBreakerAssertion
/// @author Phylax Systems
/// @notice Standalone EVK asset-flow circuit breaker for incremental rollout.
contract EulerEVaultCircuitBreakerAssertion is EulerEVaultCircuitBreakerMixin {
    constructor(address asset_, uint256 inflowThresholdBps_, uint256 inflowWindowDuration_)
        EulerEVaultCircuitBreakerMixin(asset_, inflowThresholdBps_, inflowWindowDuration_)
    {}

    /// @notice Registers inflow hard-pause plus the two outflow response tiers.
    function triggers() external view override {
        _registerCircuitBreakers();
    }
}
