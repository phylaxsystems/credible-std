// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {RoycoKernelCumulativeOutflowAssertion} from "./RoycoKernelCumulativeOutflowAssertion.sol";

/// @title RoycoKernelCumulativeFlowAssertion
/// @author Phylax Systems
/// @notice Circuit breaker that trips on large cumulative inflows or outflows of Royco tranche
///         assets through the kernel within rolling windows.
/// @dev Royco LP deposits and redemptions both settle through the kernel, so the kernel's ST/JT
///      custody balances are the right surface for both inflow and outflow breakers.
abstract contract RoycoKernelCumulativeFlowAssertion is RoycoKernelCumulativeOutflowAssertion {
    /// @notice Maximum cumulative inflow as basis points of the kernel-balance snapshot.
    uint256 public immutable inflowThresholdBps;

    /// @notice Rolling inflow window length in seconds.
    uint256 public immutable inflowWindowDuration;

    constructor(
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_,
        uint256 inflowThresholdBps_,
        uint256 inflowWindowDuration_
    ) RoycoKernelCumulativeOutflowAssertion(outflowThresholdBps_, outflowWindowDuration_) {
        inflowThresholdBps = inflowThresholdBps_;
        inflowWindowDuration = inflowWindowDuration_;
    }

    /// @notice Registers both cumulative outflow and inflow triggers for Royco tranche assets.
    function _registerCumulativeFlowTriggers() internal view {
        _registerCumulativeOutflowTriggers();
        _registerCumulativeInflowTriggers();
    }

    /// @notice Registers the cumulative inflow triggers for Royco tranche assets.
    function _registerCumulativeInflowTriggers() internal view {
        watchCumulativeInflow(stAsset, inflowThresholdBps, inflowWindowDuration, this.assertCumulativeInflow.selector);

        if (!_hasIdenticalAssets()) {
            watchCumulativeInflow(
                jtAsset, inflowThresholdBps, inflowWindowDuration, this.assertCumulativeInflow.selector
            );
        }
    }

    /// @notice Called when the cumulative inflow breaker trips.
    function assertCumulativeInflow() external virtual {
        PhEvm.InflowContext memory ctx = ph.inflowContext();

        if (_hasIdenticalAssets()) {
            revert("Royco: cumulative tranche-asset inflow breaker tripped");
        }

        if (ctx.token == stAsset) {
            revert("Royco: senior tranche asset inflow breaker tripped");
        }

        if (ctx.token == jtAsset) {
            revert("Royco: junior tranche asset inflow breaker tripped");
        }

        revert("Royco: cumulative kernel inflow breaker tripped");
    }
}
