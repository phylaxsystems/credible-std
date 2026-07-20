// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {CapLiquidationHelpers} from "./CapLiquidationHelpers.sol";
import {ICapLenderLike} from "./CapLiquidationInterfaces.sol";

/// @title CapLiquidationAssertion
/// @author Phylax Systems
/// @notice Keeps Cap liquidations honest: a liquidation must actually repay the borrower's debt,
///         and its proceeds must stay in the protocol as backing rather than draining the vault.
/// @dev Deploy against the Cap `Lender`. A liquidation repays an agent's debt from the
///      liquidator's funds and, in exchange, slashes the agent's restaked delegation collateral to
///      the liquidator. Each check is scoped to a single `liquidate` call via PreCall/PostCall
///      snapshots, so unrelated operations in the same transaction never contaminate it.
///
///      1. Debt is repaid (`assertLiquidationReducesDebt`): a liquidation that moves value
///         (`amount > 0`) must strictly reduce the agent's debt for the liquidated asset. This is
///         the "no liquidation without repaying debt" guarantee — collateral cannot be seized
///         while the borrower's liability is left untouched. (A successful `liquidate` always has
///         a liquidatable agent, so any positive amount repays a positive amount.)
///
///      2. Backing is retained (`assertLiquidationRetainsBacking`): the vault's claimable backing
///         for the asset (`availableBalance = totalSupplies - totalBorrows`) may not fall below its
///         pre-call value minus the restaker interest the liquidation legitimately realizes from
///         the vault. Repaid principal flows back into the vault (raising claimable backing); the
///         only sanctioned reduction is restaker-interest realization. Anything more means the
///         liquidation path drained backing instead of leaving the proceeds in the protocol.
contract CapLiquidationAssertion is CapLiquidationHelpers {
    constructor() {
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertLiquidationReducesDebt.selector, ICapLenderLike.liquidate.selector);
        registerFnCallTrigger(this.assertLiquidationRetainsBacking.selector, ICapLenderLike.liquidate.selector);
    }

    /// @notice A value-moving liquidation must reduce the protocol-reported debt.
    /// @dev `debt()` already includes accrued restaker interest in the official implementation,
    ///      so adding that interest again would permit a liquidation that leaves debt unchanged.
    function assertLiquidationReducesDebt() external view {
        LiquidationCall memory liq = _resolveLiquidation();
        if (liq.amount == 0) return;

        PhEvm.ForkId memory pre = _preCall(liq.callStart);
        uint256 debtPre = _debtAt(liq.agent, liq.asset, pre);
        uint256 debtPost = _debtAt(liq.agent, liq.asset, _postCall(liq.callEnd));
        require(debtPost < debtPre, "CapLiquidation: debt not reduced");
    }

    /// @notice A liquidation must not drain the vault's claimable backing for the asset.
    /// @dev Fires per `liquidate` call. The vault's claimable backing may legitimately dip by the
    ///      restaker interest the repay realizes from the vault; repaid principal pushes it back
    ///      up. Fails if backing ends below `pre - realizedRestakerInterest`, meaning liquidation
    ///      proceeds were siphoned out of the vault instead of restored as backing.
    function assertLiquidationRetainsBacking() external view {
        LiquidationCall memory liq = _resolveLiquidation();

        PhEvm.ForkId memory pre = _preCall(liq.callStart);
        address vault = _vaultFor(liq.asset, pre);

        uint256 availPre = _availableBalanceAt(vault, liq.asset, pre);
        uint256 availPost = _availableBalanceAt(vault, liq.asset, _postCall(liq.callEnd));
        uint256 realized = _realizedRestakerInterestAt(liq.agent, liq.asset, pre);

        require(availPost + realized >= availPre, "CapLiquidation: backing drained by liquidation");
    }
}
