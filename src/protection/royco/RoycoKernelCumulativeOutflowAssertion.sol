// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {RoycoKernelBaseAssertion} from "./RoycoKernelBaseAssertion.sol";

/// @title RoycoKernelCumulativeOutflowAssertion
/// @author Phylax Systems
/// @notice Circuit breaker that trips when cumulative ERC-20 outflow of Royco tranche assets
///         from the kernel exceeds a configured threshold within a rolling window.
///
/// Invariant covered:
///   - **Kernel custody outflow cap**: net outflow of the senior or junior tranche asset from
///     the Royco kernel must not exceed `outflowThresholdBps` of that asset's kernel balance
///     snapshot within `outflowWindowDuration`.
///
/// @dev Royco routes user redemption flows through the kernel, which holds both tranche assets.
///      The trigger therefore watches the kernel's ST/JT custody balances instead of the tranche
///      ERC-20 share contracts.
///
///      For identical-asset markets, the trigger is registered once to avoid double-counting the
///      same kernel-held token.
///
///      Override `assertCumulativeOutflow` for smarter breaker behavior. The default
///      implementation is a hard breaker.
abstract contract RoycoKernelCumulativeOutflowAssertion is RoycoKernelBaseAssertion {
    /// @notice Maximum cumulative outflow as basis points of the kernel-balance snapshot.
    uint256 public immutable outflowThresholdBps;

    /// @notice Rolling window length in seconds.
    uint256 public immutable outflowWindowDuration;

    constructor(uint256 thresholdBps_, uint256 windowDuration_) {
        outflowThresholdBps = thresholdBps_;
        outflowWindowDuration = windowDuration_;
    }

    /// @notice Registers the cumulative outflow triggers for Royco tranche assets.
    function _registerCumulativeOutflowTriggers() internal view {
        watchCumulativeOutflow(stAsset, outflowThresholdBps, outflowWindowDuration, this.assertCumulativeOutflow.selector);

        if (!_hasIdenticalAssets()) {
            watchCumulativeOutflow(jtAsset, outflowThresholdBps, outflowWindowDuration, this.assertCumulativeOutflow.selector);
        }
    }

    /// @notice Called when the cumulative outflow breaker trips.
    function assertCumulativeOutflow() external virtual {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();

        if (_hasIdenticalAssets()) {
            revert("Royco: cumulative tranche-asset outflow breaker tripped");
        }

        if (ctx.token == stAsset) {
            revert("Royco: senior tranche asset outflow breaker tripped");
        }

        if (ctx.token == jtAsset) {
            revert("Royco: junior tranche asset outflow breaker tripped");
        }

        revert("Royco: cumulative kernel outflow breaker tripped");
    }
}
