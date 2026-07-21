// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AnomalyGatedBaseAssertion} from "./AnomalyGatedBaseAssertion.sol";

/// @title AnomalyGatedOutflowAssertion
/// @author Phylax Systems
/// @notice Reverts only when the transaction is anomalous AND drains at least `outflowFracBps` of a
///         reserve token from the fund-holding contract. Either condition alone passes.
///
/// Invariant covered:
///   - **Gated drain**: an anomalous transaction may not move a large fraction of the watched
///     reserve out of the contract that holds it. The gate suppresses the false positive a bare
///     drain check produces on a large but benign withdrawal.
///
/// @dev The reserve custody contract (`outflowTarget`) is named separately from the anomaly focal
///      (`target`): a lending pool is scored while its aToken holds the drained reserve.
abstract contract AnomalyGatedOutflowAssertion is AnomalyGatedBaseAssertion {
    error AnomalousOutflow();

    /// @notice The contract whose reserve balance the outflow is measured from.
    address internal immutable outflowTarget;
    /// @notice The reserve token whose net outflow corroborates a drain.
    address internal immutable outflowToken;
    /// @notice Net outflow over pre-transaction balance, in bps, at or above which the drain
    ///         heuristic corroborates.
    uint256 internal immutable outflowFracBps;

    constructor(address _outflowTarget, address _token, uint256 _fracBps) {
        if (_outflowTarget == address(0) || _token == address(0) || _fracBps == 0) {
            revert HeuristicMisconfigured();
        }
        outflowTarget = _outflowTarget;
        outflowToken = _token;
        outflowFracBps = _fracBps;
    }

    /// @notice Register the anomaly trigger for the gated drain check. Call this inside `triggers()`.
    function _registerOutflowTrigger() internal view {
        _registerAnomalyTrigger(this.assertAnomalousOutflow.selector);
    }

    /// @notice Whether the drain heuristic corroborates on this transaction.
    /// @dev Overridable so the composite and adopters can reuse the corroboration alone.
    function _outflowCorroborates() internal view virtual returns (bool) {
        return _drains(outflowTarget, outflowToken, outflowFracBps);
    }

    /// @notice Reverts only when the transaction is anomalous and drains the reserve.
    function assertAnomalousOutflow() external view {
        if (!_anomalous()) {
            return;
        }
        if (_outflowCorroborates()) {
            revert AnomalousOutflow();
        }
    }
}
