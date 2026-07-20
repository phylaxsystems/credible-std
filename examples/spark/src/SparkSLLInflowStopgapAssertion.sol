// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title SparkSLLInflowStopgapAssertion
/// @author Phylax Systems
/// @notice Example Spark Liquidity Layer policy on net watched-token custody outflow.
/// @dev Mount this assertion on the SLL custody contract, e.g. Spark's `ALMProxy`,
///      once per watched underlying asset. From the SLL perspective the protected
///      action is an ERC-20 outflow from custody; from the destination venue's
///      perspective the same movement is an inflow that consumes SLL rate limits.
///
///      Spark ALM controller references:
///      - `ALMProxy` is the custody account and routes controller calls through `doCall`.
///      - `depositAave(aToken, amount)` consumes `LIMIT_AAVE_DEPOSIT`, approves the
///        aToken's underlying asset, then supplies it through the Aave/SparkLend pool.
///      - `RateLimits` refills linearly from `(maxAmount, slope)`.
///
///      The executor measures net Transfer-log flow against the ALMProxy's idle token balance.
///      Inflows can offset later outflows, and this is not venue-specific or a percentage of
///      deployed SLL assets. Treat the threshold as an opt-in custody policy calibrated from
///      actual ALMProxy traffic.
contract SparkSLLInflowStopgapAssertion is Assertion {
    /// @notice Example 0.02% policy threshold. It is not a protocol invariant.
    uint256 public constant DEFAULT_THRESHOLD_BPS = 2;

    /// @notice Spark's published response-window default used for the stopgap.
    uint256 public constant DEFAULT_WINDOW_DURATION = 6 hours;

    /// @notice Underlying ERC-20 asset leaving SLL custody.
    address public immutable watchedAsset;

    /// @notice Maximum net cumulative outflow as bps of the executor's idle-balance snapshot.
    uint256 public immutable thresholdBps;

    /// @notice Rolling window length in seconds.
    uint256 public immutable windowDuration;

    /// @param watchedAsset_ Underlying asset to monitor on the assertion adopter.
    /// @param thresholdBps_ Maximum net asset outflow in basis points of idle custody.
    /// @param windowDuration_ Rolling window, in seconds, used by the outflow trigger.
    constructor(address watchedAsset_, uint256 thresholdBps_, uint256 windowDuration_) {
        require(watchedAsset_ != address(0), "SparkSLL: zero asset");
        require(thresholdBps_ != 0 && thresholdBps_ < 10_000, "SparkSLL: invalid threshold");
        require(windowDuration_ >= 10 && windowDuration_ <= type(uint64).max, "SparkSLL: invalid window");

        watchedAsset = watchedAsset_;
        thresholdBps = thresholdBps_;
        windowDuration = windowDuration_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the SLL asset outflow breaker.
    /// @dev For the proposed Spark stopgap, deploy with `(asset, 2, 6 hours)` and
    ///      adopt this assertion on the ALMProxy that holds that asset.
    function triggers() external view override {
        watchCumulativeOutflow(watchedAsset, thresholdBps, windowDuration, this.assertHalt6hInflowBreach.selector);
    }

    /// @notice Reverts when the rolling SLL asset outflow limit has been breached.
    /// @dev The executor invokes this only after `watchCumulativeOutflow` determines
    ///      that the watched asset exceeded the configured window budget. The context
    ///      check prevents accidental reuse with the wrong token registration.
    function assertHalt6hInflowBreach() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == watchedAsset, "SparkSLL: wrong asset context");

        revert("SparkSLL: 6h venue inflow cap exceeded");
    }
}
