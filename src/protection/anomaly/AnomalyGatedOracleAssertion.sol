// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AnomalyGatedBaseAssertion} from "./AnomalyGatedBaseAssertion.sol";

/// @title AnomalyGatedOracleAssertion
/// @author Phylax Systems
/// @notice Reverts only when the transaction is anomalous AND the oracle answer returned by
///         `oracleQuery` on `oracle` moves beyond `oracleToleranceBps` across the transaction.
///         Either condition alone passes.
///
/// Invariant covered:
///   - **Gated oracle deviation**: an anomalous transaction may not rely on an oracle answer that
///     moved materially across the transaction. Covers price-manipulation and flash-loan attacks
///     that push a feed out of range to open or liquidate a position.
///
/// @dev `oracleQuery` is the full ABI-encoded read: `abi.encodeWithSignature("latestAnswer()")` for
///      a Chainlink-style feed, or `abi.encodeWithSignature("getAssetPrice(address)", asset)` for an
///      asset-priced feed. Stored, not immutable, because `bytes` cannot be immutable. The assertion
///      is non-view because the oracle read executes.
abstract contract AnomalyGatedOracleAssertion is AnomalyGatedBaseAssertion {
    error AnomalousOracle();

    /// @notice The oracle feed whose answer this observes.
    address internal immutable oracle;
    /// @notice Maximum tolerated oracle deviation across the transaction, in bps.
    uint256 internal immutable oracleToleranceBps;
    /// @notice The full ABI-encoded call that reads the oracle answer.
    bytes internal oracleQuery;

    constructor(address _oracle, bytes memory _oracleQuery, uint256 _toleranceBps) {
        if (_oracle == address(0) || _oracleQuery.length < 4) {
            revert HeuristicMisconfigured();
        }
        oracle = _oracle;
        oracleQuery = _oracleQuery;
        oracleToleranceBps = _toleranceBps;
    }

    /// @notice Register the anomaly trigger for the gated oracle check. Call this inside `triggers()`.
    function _registerOracleTrigger() internal view {
        _registerAnomalyTrigger(this.assertAnomalousOracle.selector);
    }

    /// @notice Whether the oracle heuristic corroborates on this transaction. Non-view: the oracle
    ///         read executes.
    function _oracleCorroborates() internal virtual returns (bool) {
        return _oracleDeviated(oracle, oracleQuery, oracleToleranceBps);
    }

    /// @notice Reverts only when the transaction is anomalous and the oracle answer deviates.
    function assertAnomalousOracle() external {
        if (!_anomalous()) {
            return;
        }
        if (_oracleCorroborates()) {
            revert AnomalousOracle();
        }
    }
}
