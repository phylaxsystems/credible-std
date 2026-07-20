// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {IZkLighterLike} from "./LighterBridgeInterfaces.sol";

/// @title LighterOutflowCircuitBreaker
/// @author Phylax Systems
/// @notice Rolling-window outflow circuit breaker for collateral custodied by Lighter's `ZkLighter`
///         bridge. Trips when cumulative outflow of the watched token over a rolling window exceeds a
///         fraction of the window-start balance, halting a drain before it completes.
/// @dev This is the canonical bridge invariant that cannot be expressed on-chain: each withdrawal is
///      individually bounded by the contract (it pays at most a user's credited pending balance), but
///      the contract has no notion of an aggregate rate limit across many calls in a time window. A
///      compromised validator or a buggy execute path can approve many individually-valid withdrawals
///      that together drain custody; only an off-chain rolling-window accounting can catch that.
///
///      Built on the `watchCumulativeOutflow` trigger: the executor maintains the rolling-window TVL
///      snapshots and net-outflow accounting and fires this assertion only once the configured
///      threshold is breached. The breaker then reads `ph.outflowContext()` for the breach details.
///
///      Smart breaker: once the escape hatch ("desert mode") is open, mass user exits are expected and
///      legitimate, so the breaker stands down and never reverts. This keeps it from blocking the very
///      withdrawals the escape hatch exists to enable. Deploy one instance per watched ERC-20 token
///      (native ETH cannot be watched through an ERC-20 outflow trigger).
///
///      Override `assertCollateralOutflowWithinLimit` for a smarter policy (e.g. a warning tier that
///      permits only known withdrawal selectors); `_breakerTrips` holds the default decision so it can
///      be unit-tested directly.
contract LighterOutflowCircuitBreaker is Assertion {
    /// @notice Raised when collateral leaves the bridge faster than the configured rolling-window cap
    ///         outside of an active escape hatch.
    error CollateralOutflowBreached(address token, uint256 currentBps, uint256 thresholdBps, uint256 absoluteOutflow);

    /// @notice The `ZkLighter` proxy: funds custody and assertion adopter.
    address internal immutable BRIDGE;

    /// @notice Watched ERC-20 collateral token (e.g. USDC on Lighter).
    address internal immutable COLLATERAL;

    /// @notice Maximum cumulative outflow as basis points of the window-start balance. 1000 = 10%.
    uint256 internal immutable OUTFLOW_THRESHOLD_BPS;

    /// @notice Rolling window length in seconds.
    uint256 internal immutable OUTFLOW_WINDOW_DURATION;

    constructor(address bridge_, address collateral_, uint256 outflowThresholdBps_, uint256 outflowWindowDuration_) {
        require(bridge_ != address(0), "LighterBreaker: bridge zero");
        require(collateral_ != address(0), "LighterBreaker: collateral zero");
        require(outflowThresholdBps_ != 0 && outflowThresholdBps_ < 10_000, "LighterBreaker: invalid threshold");
        require(
            outflowWindowDuration_ >= 10 && outflowWindowDuration_ <= type(uint64).max,
            "LighterBreaker: invalid window"
        );

        BRIDGE = bridge_;
        COLLATERAL = collateral_;
        OUTFLOW_THRESHOLD_BPS = outflowThresholdBps_;
        OUTFLOW_WINDOW_DURATION = outflowWindowDuration_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the cumulative-outflow circuit breaker for the watched collateral token.
    /// @dev The executor fires `assertCollateralOutflowWithinLimit` only when cumulative outflow over
    ///      `OUTFLOW_WINDOW_DURATION` exceeds `OUTFLOW_THRESHOLD_BPS` of the window-start balance.
    function triggers() external view override {
        watchCumulativeOutflow(
            COLLATERAL, OUTFLOW_THRESHOLD_BPS, OUTFLOW_WINDOW_DURATION, this.assertCollateralOutflowWithinLimit.selector
        );
    }

    /// @notice Halts a collateral drain that breaches the rolling-window cap during normal operation.
    /// @dev Fires only on breach. Reverts unless the bridge is in desert mode, in which case the
    ///      breaker stands down because mass exits are expected. A failure means more than
    ///      `OUTFLOW_THRESHOLD_BPS` of the window-start collateral balance has left the bridge within
    ///      the window — likely a drain in progress.
    function assertCollateralOutflowWithinLimit() external view virtual {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ph.getAssertionAdopter() == BRIDGE, "LighterBreaker: configured bridge is not adopter");
        if (!_breakerTrips(ctx.currentBps, OUTFLOW_THRESHOLD_BPS, _bridgeInDesertModeAt(_preTx()))) {
            return;
        }
        revert CollateralOutflowBreached(ctx.token, ctx.currentBps, OUTFLOW_THRESHOLD_BPS, ctx.absoluteOutflow);
    }

    /// @notice Pure breaker decision: trip when the breach is real and the escape hatch is closed.
    /// @dev Returns false in desert mode (mass exits are legitimate) and false below threshold (a
    ///      defensive guard against a sub-threshold context, even though the trigger only fires on
    ///      breach). Kept pure so the production decision is exactly what the unit tests exercise.
    function _breakerTrips(uint256 currentBps, uint256 thresholdBps, bool inDesertMode) internal pure returns (bool) {
        if (inDesertMode) {
            return false;
        }
        return currentBps > thresholdBps;
    }

    /// @notice Reads the bridge's desert-mode flag at the supplied snapshot.
    function _bridgeInDesertModeAt(PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(BRIDGE, abi.encodeCall(IZkLighterLike.desertMode, ()), fork);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "LighterBreaker: state read failed";
    }
}
