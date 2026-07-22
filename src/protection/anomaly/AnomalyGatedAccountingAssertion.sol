// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AnomalyGatedBaseAssertion} from "./AnomalyGatedBaseAssertion.sol";

/// @title AnomalyGatedAccountingAssertion
/// @author Phylax Systems
/// @notice Reverts only when the transaction is anomalous AND the ERC-4626 share price of `vault`
///         moves beyond `shareToleranceBps` across the transaction. Either condition alone passes.
///
/// Invariant covered:
///   - **Gated accounting break**: an anomalous transaction may not move a vault's share price
///     beyond tolerance. Covers share-inflation and donation attacks that leave the vault's own
///     balance untouched while distorting the price at which shares redeem.
///
/// @dev Generic across ERC-4626-shaped vaults; the constructor parameters are the only
///      per-deployment difference. An empty vault (zero supply) is skipped by the precompile.
abstract contract AnomalyGatedAccountingAssertion is AnomalyGatedBaseAssertion {
    error AnomalousAccounting();

    /// @notice The ERC-4626-shaped vault whose share price this observes.
    address internal immutable accountingVault;
    /// @notice Maximum tolerated share-price deviation across the transaction, in bps.
    uint256 internal immutable shareToleranceBps;

    constructor(address _vault, uint256 _toleranceBps) {
        if (_vault == address(0)) {
            revert HeuristicMisconfigured();
        }
        accountingVault = _vault;
        shareToleranceBps = _toleranceBps;
    }

    /// @notice Register the anomaly trigger for the gated accounting check. Call this in `triggers()`.
    function _registerAccountingTrigger() internal view {
        _registerAnomalyTrigger(this.assertAnomalousAccounting.selector);
    }

    /// @notice Whether the accounting heuristic corroborates on this transaction.
    function _accountingCorroborates() internal view virtual returns (bool) {
        return _accountingBroke(accountingVault, shareToleranceBps);
    }

    /// @notice Reverts only when the transaction is anomalous and the share price leaves tolerance.
    function assertAnomalousAccounting() external view {
        if (!_anomalous()) {
            return;
        }
        if (_accountingCorroborates()) {
            revert AnomalousAccounting();
        }
    }
}
