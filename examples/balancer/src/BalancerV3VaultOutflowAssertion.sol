// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title BalancerV3VaultOutflowAssertion
/// @author Phylax Systems
/// @notice Rolling-window circuit breaker on one token leaving the Balancer V3 Vault's custody.
/// @dev Apply to the Vault singleton. The Vault custodies every pool's liquidity for a token, so a
///      drain of any single pool, buffer, or fee path ultimately shows up as that token leaving the
///      Vault's ERC20 balance. This breaker is flow-based rather than selector-based: it does not
///      care which Router, hook, or admin path moved the funds, only how fast custody is leaving,
///      which is the one bound that survives a bug in any individual code path.
///
///      The breaker counts all exits, including honest large withdrawals and batch settlements, so
///      the threshold must sit above the largest legitimate single-window outflow observed for the
///      deployment. Calibrate per token from historical Vault flow before adoption; a breaker that
///      trips on an honest whale exit is worse than none.
contract BalancerV3VaultOutflowAssertion is Assertion {
    /// @notice Balancer V3 Vault singleton whose token custody is rate-limited (the adopter).
    address public immutable vault;

    /// @notice Token whose outflow is watched.
    address public immutable token;

    /// @notice Cumulative outflow cap as bps of the token balance at window start. 2000 = 20%.
    uint256 public immutable outflowThresholdBps;

    /// @notice Rolling window length, in seconds, over which the cap is enforced.
    uint256 public immutable outflowWindowDuration;

    constructor(address vault_, address token_, uint256 outflowThresholdBps_, uint256 outflowWindowDuration_) {
        require(vault_ != address(0), "BalancerV3Outflow: zero vault");
        require(token_ != address(0), "BalancerV3Outflow: zero token");
        require(outflowThresholdBps_ != 0 && outflowThresholdBps_ <= 10_000, "BalancerV3Outflow: bad threshold");
        require(outflowWindowDuration_ != 0, "BalancerV3Outflow: zero window");

        vault = vault_;
        token = token_;
        outflowThresholdBps = outflowThresholdBps_;
        outflowWindowDuration = outflowWindowDuration_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the rolling-window outflow breaker on the watched token.
    /// @dev The executor tracks the rolling outflow internally and invokes the assertion only once
    ///      the watched token's cumulative outflow crosses the threshold, so reaching the assertion
    ///      already means the rate limit was breached.
    function triggers() external view override {
        watchCumulativeOutflow(
            token, outflowThresholdBps, outflowWindowDuration, this.assertOutflowWithinLimit.selector
        );
    }

    /// @notice Hard circuit breaker for token outflow from the Vault.
    /// @dev Invoked only after the cumulative outflow already exceeded the threshold, so it reverts
    ///      unconditionally: the offending transaction is never included and the team can triage.
    ///      A legitimate outflow above the cap must be split across windows or the limit raised.
    function assertOutflowWithinLimit() external pure {
        revert("BalancerV3Outflow: vault token outflow circuit breaker tripped");
    }
}
