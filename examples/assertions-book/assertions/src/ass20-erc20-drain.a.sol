// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ERC20CumulativeOutflowBreakerAssertion is Assertion {
    address public immutable monitoredToken;
    uint256 public immutable outflowThresholdBps;
    uint256 public immutable outflowWindowDuration;

    constructor(address monitoredToken_, uint256 outflowThresholdBps_, uint256 outflowWindowDuration_) {
        registerAssertionSpec(AssertionSpec.Reshiram);

        monitoredToken = monitoredToken_;
        outflowThresholdBps = outflowThresholdBps_;
        outflowWindowDuration = outflowWindowDuration_;
    }

    function triggers() external view override {
        watchCumulativeOutflow(
            monitoredToken,
            outflowThresholdBps,
            outflowWindowDuration,
            this.assertCumulativeOutflow.selector
        );
    }

    /// @notice Reverts when cumulative token outflow breaches the rolling-window limit.
    /// @dev The Reshiram trigger tracks the window and calls this function only after breach.
    function assertCumulativeOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == monitoredToken, "ERC20Outflow: wrong token context");

        revert("ERC20Outflow: cumulative outflow breaker tripped");
    }
}
