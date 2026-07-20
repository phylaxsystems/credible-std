// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title BalancerV3VaultOutflowAssertion
/// @author Phylax Systems
/// @notice Rolling-window circuit breaker on one token's NET outflow from the Balancer V3 Vault's
///         custody.
/// @dev Apply to the Vault singleton. The Vault custodies every pool's liquidity for a token, so a
///      drain of any single pool, buffer, or fee path ultimately shows up as that token leaving the
///      Vault's ERC20 balance. This breaker is flow-based rather than selector-based: it does not
///      care which Router, hook, or admin path moved the funds, only how fast custody is leaving,
///      which is the one bound that survives a bug in any individual code path.
///
///      What the executor actually measures, stated exactly:
///      - The threshold is on NET flow (`cumulativeOutflow - cumulativeInflow`) within the rolling
///        window, as bps of the token balance snapshotted at window start. Inflows from ANY source
///        sharing the singleton — deposits into unrelated pools, buffer traffic — offset exits, so
///        a 400-token drain behind a 250-token deposit measures as 150 tokens of outflow. This is
///        drain protection for sustained custody loss, not a gross-exit bound; a gross bound would
///        need an absolute-outflow or pool-aware trigger, which `watchCumulativeOutflow` is not.
///      - The breaker is value-blind and token-scoped. A canonical ERC-4626 buffer rebalance wraps
///        underlying out of custody while wrapped shares flow in: value-preserving for the Vault,
///        but the underlying watcher counts the full wrap as outflow. On deployments where the
///        watched token backs an active buffer, the threshold must sit above the largest expected
///        wrap, or the watched token should be one without buffer traffic.
///      - Aggregate protocol-fee collection (`collectAggregateFees`) transfers the ENTIRE accrued
///        fee ledger in one call — it has no amount parameter and cannot be split across windows.
///        Collection cadence must keep the accrued ledger below the cap; a legitimate operation
///        that has already outgrown the cap can only proceed by raising the limit or temporarily
///        deactivating this assertion through the protocol's Credible Layer management flow.
///
///      The cap therefore must be calibrated per token from historical Vault flow — above the
///      largest legitimate single-window net outflow (whale exits, batch settlements, buffer
///      rebalances, fee collection) — before adoption. A breaker that trips on honest traffic is
///      worse than none.
contract BalancerV3VaultOutflowAssertion is Assertion {
    /// @notice Balancer V3 Vault singleton whose token custody is rate-limited (the adopter).
    address public immutable vault;

    /// @notice Token whose net outflow is watched.
    address public immutable token;

    /// @notice Net outflow cap as bps of the token balance at window start. 2000 = 20%.
    uint256 public immutable outflowThresholdBps;

    /// @notice Rolling window length, in seconds, over which the cap is enforced.
    uint256 public immutable outflowWindowDuration;

    /// @dev The executor buckets flow in 10-second granules and stores window state in `u64`
    ///      fields; a window below one bucket or beyond `u64` deploys fine and then fails trigger
    ///      registration, so both bounds are enforced here where they are visible at deploy time.
    uint256 internal constant MIN_WINDOW_DURATION = 10;

    constructor(address vault_, address token_, uint256 outflowThresholdBps_, uint256 outflowWindowDuration_) {
        require(vault_ != address(0), "BalancerV3Outflow: zero vault");
        require(token_ != address(0), "BalancerV3Outflow: zero token");
        // 10_000 bps is unreachable, not permissive: the executor dispatches only when net outflow
        // STRICTLY exceeds the threshold, and net outflow can never exceed the window-start
        // balance, so a full drain lands exactly on 100% and would never fire the breaker.
        require(outflowThresholdBps_ != 0 && outflowThresholdBps_ < 10_000, "BalancerV3Outflow: bad threshold");
        require(
            outflowWindowDuration_ >= MIN_WINDOW_DURATION && outflowWindowDuration_ <= type(uint64).max,
            "BalancerV3Outflow: bad window"
        );

        vault = vault_;
        token = token_;
        outflowThresholdBps = outflowThresholdBps_;
        outflowWindowDuration = outflowWindowDuration_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the rolling-window outflow breaker on the watched token.
    /// @dev The executor tracks the rolling net outflow internally and invokes the assertion only
    ///      once the watched token's cumulative net outflow crosses the threshold, so reaching the
    ///      assertion already means the rate limit was breached. Virtual so tests can subclass
    ///      with a call trigger and drive the breaker through real assertion dispatch (the flow
    ///      trigger itself is executor-driven and not simulated by local `pcl test`).
    function triggers() external view virtual override {
        watchCumulativeOutflow(
            token, outflowThresholdBps, outflowWindowDuration, this.assertOutflowWithinLimit.selector
        );
    }

    /// @notice Hard circuit breaker for net token outflow from the Vault.
    /// @dev Invoked only after the cumulative net outflow already exceeded the threshold. The flow
    ///      watcher tracks the assertion ADOPTER's balance, so the configured Vault is checked
    ///      against the adopter first: adopting this assertion on any other account fails loudly
    ///      here instead of silently rate-limiting that account while the Vault goes unprotected.
    ///      Past that check it reverts unconditionally: the offending transaction is never
    ///      included and the team can triage.
    function assertOutflowWithinLimit() external view {
        require(ph.getAssertionAdopter() == vault, "BalancerV3Outflow: configured vault is not adopter");
        revert("BalancerV3Outflow: vault token outflow circuit breaker tripped");
    }
}
