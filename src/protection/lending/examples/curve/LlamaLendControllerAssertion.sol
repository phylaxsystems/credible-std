// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";
import {LlamaLendControllerProtocolHelpers} from "./LlamaLendProtocol.sol";

/// @title LlamaLendControllerAssertion
/// @notice Example LlamaLend controller checks for borrowed-token custody, borrow-cap enforcement,
///         and hard cumulative inflow/outflow circuit breakers.
contract LlamaLendControllerAssertion is LlamaLendControllerProtocolHelpers {
    uint256 public constant INFLOW_THRESHOLD_BPS = 1_000;
    uint256 public constant INFLOW_WINDOW_DURATION = 6 hours;
    uint256 public constant OUTFLOW_THRESHOLD_BPS = 1_000;
    uint256 public constant OUTFLOW_WINDOW_DURATION = 24 hours;

    constructor(address controller_, uint256 availableBalanceTolerance_)
        LlamaLendControllerProtocolHelpers(controller_, availableBalanceTolerance_)
    {}

    /// @notice Registers checks over controller token custody, post-borrow debt caps,
    ///         and 10% borrowed-token inflow/outflow caps over rolling 6 hour / 24 hour windows.
    function triggers() external view override {
        watchCumulativeInflow(
            borrowedToken, INFLOW_THRESHOLD_BPS, INFLOW_WINDOW_DURATION, this.assertCumulativeInflow.selector
        );
        watchCumulativeOutflow(
            borrowedToken, OUTFLOW_THRESHOLD_BPS, OUTFLOW_WINDOW_DURATION, this.assertCumulativeOutflow.selector
        );
        registerTxEndTrigger(this.assertControllerCustodyCoversAvailableBalance.selector);
        _registerLlamaLendDebtIncreasingTriggers(this.assertDebtIncreaseWithinBorrowCap.selector);
    }

    /// @notice Hard circuit breaker that blocks transactions while cumulative inflow stays above threshold.
    function assertCumulativeInflow() external pure {
        revert("LlamaLend: cumulative inflow breaker tripped");
    }

    /// @notice Hard circuit breaker that blocks transactions while cumulative outflow stays above threshold.
    function assertCumulativeOutflow() external pure {
        revert("LlamaLend: cumulative outflow breaker tripped");
    }

    /// @notice Checks controller token custody covers `available_balance()`.
    function assertControllerCustodyCoversAvailableBalance() external {
        PhEvm.ForkId memory fork = _postTx();
        require(
            _llamaControllerBorrowedBalanceAt(fork) + availableBalanceTolerance
                >= _llamaControllerAvailableBalanceAt(fork),
            "LlamaLend: borrowed custody below available balance"
        );
    }

    /// @notice Checks debt-increasing actions leave `total_debt()` at or below `borrow_cap()`.
    function assertDebtIncreaseWithinBorrowCap() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        uint256 preTotalDebt = _llamaControllerTotalDebtAt(_preCall(ctx.callStart));
        uint256 postTotalDebt = _llamaControllerTotalDebtAt(_postCall(ctx.callEnd));

        if (postTotalDebt <= preTotalDebt) {
            return;
        }

        require(postTotalDebt <= _llamaControllerBorrowCapAt(_postCall(ctx.callEnd)), "LlamaLend: borrow cap exceeded");
    }
}
