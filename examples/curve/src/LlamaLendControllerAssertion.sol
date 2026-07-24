// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {LlamaLendControllerProtocolHelpers} from "./LlamaLendProtocol.sol";

/// @title LlamaLendControllerAssertion
/// @notice Example LlamaLend controller checks for borrowed-token custody and borrow-cap enforcement.
contract LlamaLendControllerAssertion is LlamaLendControllerProtocolHelpers {
    constructor(address controller_, address borrowedToken_, uint256 availableBalanceTolerance_)
        LlamaLendControllerProtocolHelpers(controller_, borrowedToken_, availableBalanceTolerance_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers controller token custody and post-borrow debt-cap checks.
    /// @dev Fixed rolling flow policies were removed because they measured net idle-token flow,
    ///      rejected initialization and safety-improving repayments, and were not protocol facts.
    function triggers() external view override {
        registerTxEndTrigger(this.assertControllerCustodyCoversAvailableBalance.selector);
        _registerLlamaLendDebtIncreasingTriggers(this.assertDebtIncreaseWithinBorrowCap.selector);
    }

    /// @notice Checks controller token custody covers `available_balance()`.
    function assertControllerCustodyCoversAvailableBalance() external {
        require(ph.getAssertionAdopter() == controller, "LlamaLend: configured controller is not adopter");
        PhEvm.ForkId memory fork = _postTx();
        require(
            _llamaControllerBorrowedBalanceAt(fork) + availableBalanceTolerance
                >= _llamaControllerAvailableBalanceAt(fork),
            "LlamaLend: borrowed custody below available balance"
        );
    }

    /// @notice Checks debt-increasing actions leave `total_debt()` at or below `borrow_cap()`.
    function assertDebtIncreaseWithinBorrowCap() external {
        require(ph.getAssertionAdopter() == controller, "LlamaLend: configured controller is not adopter");
        PhEvm.TriggerContext memory ctx = ph.context();
        uint256 preTotalDebt = _llamaControllerTotalDebtAt(_preCall(ctx.callStart));
        uint256 postTotalDebt = _llamaControllerTotalDebtAt(_postCall(ctx.callEnd));

        if (postTotalDebt <= preTotalDebt) {
            return;
        }

        require(postTotalDebt <= _llamaControllerBorrowCapAt(_postCall(ctx.callEnd)), "LlamaLend: borrow cap exceeded");
    }
}
