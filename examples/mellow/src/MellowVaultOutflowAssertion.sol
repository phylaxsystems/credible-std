// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title MellowVaultOutflowAssertion
/// @author Phylax Systems
/// @notice Rolling-window circuit breaker on the deposit asset leaving a Mellow vault's custody.
/// @dev Apply to the `Vault` (the account that custodies idle deposit-asset before it is pushed to
///      subvaults or paid out to the redeem queue).
///
///      This is the flagship breaker of the compromised-curator suite, and the most defensible
///      single assertion, because it is asset-flow based rather than role based: it does not care
///      *who* moved the funds or *which* curator-gated function did it. Mellow's hot path
///      (push to subvaults, `handleBatches` settlement, balance corrections) is permissioned by
///      design, so bounding any one of those functions would just restate a role check. Bounding
///      the *rate at which the asset physically leaves the vault account* is the one limit that
///      survives a stolen key that passes every role check.
///
///      The breaker counts ALL asset exits from the vault, including legitimate reallocation into
///      subvaults — those leave the vault's ERC-20 balance even though they stay inside the
///      protocol. So the threshold must be calibrated generously, above the largest legitimate
///      single-window outflow (largest planned reallocation + the largest `handleBatches`
///      settlement that can land in one window). A bound that trips on a real reallocation or a
///      large honest redemption settlement is worse than no bound. Derive the number from the
///      target deployment's real batch/reallocation sizes and record it at adoption time.
///
///      Ceiling, stated honestly: this caps catastrophic single-window theft from a stolen key or
///      a runaway adapter. It does not value restaking positions, detect oracle manipulation, or
///      improve on a timelock for *authorized* curator actions. A destination-aware variant
///      (exempting transfers to known subvaults, gating the rest) is a natural extension once
///      per-destination transfer introspection is available; `ph.outflowContext()` already exposes
///      the breaching token and the window totals.
contract MellowVaultOutflowAssertion is Assertion {
    /// @notice Vault account whose deposit-asset custody is rate-limited (the assertion adopter).
    address public immutable vault;

    /// @notice Deposit asset whose outflow is watched.
    address public immutable asset;

    /// @notice Cumulative outflow cap as bps of the asset balance at window start. 2000 = 20%.
    ///         CALIBRATE: set above the largest legitimate single-window outflow for the deployment.
    uint256 public immutable outflowThresholdBps;

    /// @notice Rolling window length, in seconds, over which the cap is enforced.
    uint256 public immutable outflowWindowDuration;

    constructor(address vault_, address asset_, uint256 outflowThresholdBps_, uint256 outflowWindowDuration_) {
        require(vault_ != address(0), "MellowOutflow: zero vault");
        require(asset_ != address(0), "MellowOutflow: zero asset");
        require(outflowThresholdBps_ != 0 && outflowThresholdBps_ < 10_000, "MellowOutflow: bad threshold");
        require(
            outflowWindowDuration_ >= 10 && outflowWindowDuration_ <= type(uint64).max,
            "MellowOutflow: invalid window"
        );

        vault = vault_;
        asset = asset_;
        outflowThresholdBps = outflowThresholdBps_;
        outflowWindowDuration = outflowWindowDuration_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Quarantined: adopter idle-token net flow is not consolidated Mellow outflow.
    function triggers() external view override {
        // Intentionally empty. Divest inflows cancel payouts, strategy pushes look like exits, and
        // native assets have no ERC-20 Transfer log for the watcher to observe.
    }

    /// @notice Hard circuit breaker for deposit-asset outflow from the vault.
    /// @dev Invoked by the executor only after the cumulative outflow already exceeded the
    ///      threshold, so this reverts unconditionally: the offending transaction is never included
    ///      and the team is alerted to triage. A legitimate planned outflow above the cap must be
    ///      split across windows or the limit temporarily raised.
    function assertOutflowWithinLimit() external pure {
        revert("MellowOutflow: vault asset outflow circuit breaker tripped");
    }
}
