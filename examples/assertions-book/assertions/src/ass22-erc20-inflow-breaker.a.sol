// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ERC20CumulativeInflowBreakerAssertion is Assertion {
    address public immutable monitoredToken;
    uint256 public immutable inflowThresholdBps;
    uint256 public immutable inflowWindowDuration;

    constructor(address monitoredToken_, uint256 inflowThresholdBps_, uint256 inflowWindowDuration_) {
        registerAssertionSpec(AssertionSpec.Reshiram);

        monitoredToken = monitoredToken_;
        inflowThresholdBps = inflowThresholdBps_;
        inflowWindowDuration = inflowWindowDuration_;
    }

    function triggers() external view override {
        watchCumulativeInflow(
            monitoredToken,
            inflowThresholdBps,
            inflowWindowDuration,
            this.assertCumulativeInflow.selector
        );
    }

    /// @notice Reverts when cumulative token inflow breaches the rolling-window limit.
    /// @dev The Reshiram trigger tracks the window and calls this function only after breach.
    function assertCumulativeInflow() external view {
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ctx.token == monitoredToken, "ERC20Inflow: wrong token context");

        revert("ERC20Inflow: cumulative inflow breaker tripped");
    }
}
