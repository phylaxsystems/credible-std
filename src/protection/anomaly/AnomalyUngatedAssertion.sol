// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AnomalyGatedBaseAssertion} from "./AnomalyGatedBaseAssertion.sol";

/// @title AnomalyUngatedAssertion
/// @author Phylax Systems
/// @notice Reverts on every transaction the anomaly trigger fires on, with no damage check.
/// @dev Blocks benign traffic by design: the invalidation count is the level's false-positive
///      budget. Use it to measure what a level costs, not as a production posture.
abstract contract AnomalyUngatedAssertion is AnomalyGatedBaseAssertion {
    /// @notice The transaction cleared the registered sensitivity level.
    error AnomalousTransaction(uint8 firesAt);

    /// @notice Register the trigger for the bare check. Call this inside `triggers()`.
    function _registerUngatedTrigger() internal view {
        _registerAnomalyTrigger(this.assertNotAnomalous.selector);
    }

    /// @notice Reverts unconditionally.
    /// @dev The trigger is the gate, so reaching here means the model already scored `target` past
    ///      `sensitivity`.
    function assertNotAnomalous() external view {
        revert AnomalousTransaction(ph.anomalyContext(target).firesAt);
    }
}
