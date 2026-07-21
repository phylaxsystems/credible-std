// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AnomalyGatedBaseAssertion} from "./AnomalyGatedBaseAssertion.sol";

/// @title AnomalyGatedUpgradeAssertion
/// @author Phylax Systems
/// @notice Reverts only when the transaction is anomalous AND a watched configuration slot changes
///         on the watched contract: the EIP-1967 implementation slot, the EIP-1967 admin slot, or
///         the supplied `ownerSlot` when non-zero. Either condition alone passes.
///
/// Invariant covered:
///   - **Gated config change**: an anomalous transaction may not rewrite the proxy implementation,
///     the proxy admin, or the owner slot. A contract does not rewrite its own implementation in
///     normal use, so the upgrade heuristic adds almost no false blocks.
///
/// @dev The watched contract (`upgradeTarget`) is named separately from the anomaly focal
///      (`target`), mirroring the drain heuristic's `outflowTarget`: a lending pool is scored while
///      the custody aToken sits behind its own proxy. `address(0)` watches the focal.
abstract contract AnomalyGatedUpgradeAssertion is AnomalyGatedBaseAssertion {
    error AnomalousUpgrade();

    /// @notice The contract whose slots the upgrade heuristic watches, or `address(0)` to watch the
    ///         anomaly focal `target`.
    address internal immutable upgradeTarget;
    /// @notice An extra owner-shaped slot to watch, or `bytes32(0)` to watch only the EIP-1967 slots.
    bytes32 internal immutable ownerSlot;

    constructor(address _upgradeTarget, bytes32 _ownerSlot) {
        upgradeTarget = _upgradeTarget;
        ownerSlot = _ownerSlot;
    }

    /// @notice Register the anomaly trigger for the gated upgrade check. Call this inside `triggers()`.
    function _registerUpgradeTrigger() internal view {
        _registerAnomalyTrigger(this.assertAnomalousUpgrade.selector);
    }

    /// @notice Whether the upgrade heuristic corroborates on this transaction.
    function _upgradeCorroborates() internal view virtual returns (bool) {
        return _upgraded(upgradeTarget, ownerSlot);
    }

    /// @notice Reverts only when the transaction is anomalous and a watched config slot changes.
    function assertAnomalousUpgrade() external view {
        if (!_anomalous()) {
            return;
        }
        if (_upgradeCorroborates()) {
            revert AnomalousUpgrade();
        }
    }
}
