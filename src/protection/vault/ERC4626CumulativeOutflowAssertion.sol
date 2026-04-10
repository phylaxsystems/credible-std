// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {IERC4626} from "./IERC4626.sol";
import {ERC4626BaseAssertion} from "./ERC4626BaseAssertion.sol";

/// @title ERC4626CumulativeOutflowAssertion
/// @author Phylax Systems
/// @notice Circuit breaker that triggers when cumulative ERC-20 outflow from the vault
///         exceeds a percentage threshold within a rolling time window.
///
/// Invariant covered:
///   - **Cumulative outflow cap**: the net outflow of the vault's underlying asset must not
///     exceed `outflowThresholdBps` of the TVL snapshot within a rolling `outflowWindowDuration`.
///
/// @dev Uses `watchCumulativeOutflow` trigger registration — the executor handles all persistent
///      state tracking, TVL snapshots, and threshold enforcement internally. The assertion
///      function fires only when the threshold is breached.
///
///      Override `assertCumulativeOutflow` for smart breaker logic (e.g. deposit/repay-only mode).
///      The default implementation unconditionally reverts (hard breaker).
abstract contract ERC4626CumulativeOutflowAssertion is ERC4626BaseAssertion {
    /// @notice Maximum cumulative outflow as basis points of the TVL snapshot. 1000 = 10%.
    uint256 public immutable outflowThresholdBps;

    /// @notice Rolling window length in seconds.
    uint256 public immutable outflowWindowDuration;

    constructor(uint256 _thresholdBps, uint256 _windowDuration) {
        outflowThresholdBps = _thresholdBps;
        outflowWindowDuration = _windowDuration;
    }

    /// @notice Register the cumulative outflow circuit breaker trigger.
    /// @dev Call this inside your `triggers()`.
    function _registerCumulativeOutflowTriggers() internal view {
        watchCumulativeOutflow(asset, outflowThresholdBps, outflowWindowDuration, this.assertCumulativeOutflow.selector);
    }

    /// @notice Called when cumulative outflow exceeds the threshold.
    /// @dev Default is a hard breaker (unconditional revert). Override for smart breaker
    ///      logic — e.g. allow deposits but block withdrawals using `ph.outflowContext()`
    ///      and `_matchingCalls()`.
    function assertCumulativeOutflow() external virtual {
        revert("ERC4626: cumulative outflow breaker tripped");
    }
}
