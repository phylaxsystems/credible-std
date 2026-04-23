// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {
    IRoycoKernel,
    RoycoAssetClaims,
    RoycoKernelHelpers,
    RoycoMarketState,
    RoycoSyncedAccountingState
} from "./RoycoHelpers.sol";

/// @title RoycoKernelAccountingAssertion
/// @author Phylax Systems
/// @notice Kernel-side Royco invariant checks for accounting conservation, coverage, recovery
///         ordering, self-liquidation deleveraging, and JT IL erasure on perpetual transitions.
/// @dev Adopt this on the Royco kernel. These checks intentionally read the accountant's synced
///      state rather than inferring accounting from raw token balance deltas.
abstract contract RoycoKernelAccountingAssertion is RoycoKernelHelpers {
    /// @notice Registers the full kernel/accountant invariant set.
    function _registerAccountingInvariantTriggers() internal view {
        _registerKernelMutationTriggers(this.assertNavConservation.selector);
        _registerKernelMutationTriggers(this.assertPerpetualHealth.selector);
        _registerKernelMutationTriggers(this.assertRecoveryPriority.selector);
        _registerKernelMutationTriggers(this.assertJtImpermanentLossErasure.selector);

        registerFnCallTrigger(this.assertCoverageFloor.selector, IRoycoKernel.stDeposit.selector);
        registerFnCallTrigger(this.assertCoverageFloor.selector, IRoycoKernel.jtRedeem.selector);
        registerFnCallTrigger(this.assertSelfLiquidationDeleveraging.selector, IRoycoKernel.stRedeem.selector);
    }

    function _registerKernelMutationTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, IRoycoKernel.syncTrancheAccounting.selector);
        registerFnCallTrigger(assertionSelector, IRoycoKernel.stDeposit.selector);
        registerFnCallTrigger(assertionSelector, IRoycoKernel.stRedeem.selector);
        registerFnCallTrigger(assertionSelector, IRoycoKernel.jtDeposit.selector);
        registerFnCallTrigger(assertionSelector, IRoycoKernel.jtRedeem.selector);
    }

    /// @notice Persisted synced accountant state must remain zero-sum across tranches.
    function assertNavConservation() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        RoycoSyncedAccountingState memory postState = _previewSyncAt(_postCall(ctx.callEnd));

        require(
            postState.stRawNAV + postState.jtRawNAV == postState.stEffectiveNAV + postState.jtEffectiveNAV,
            "Royco: NAV conservation violated"
        );
    }

    /// @notice Perpetual markets that are not already distressed must remain below the liquidation
    ///         utilization threshold after every successful kernel operation.
    function assertPerpetualHealth() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        RoycoSyncedAccountingState memory postState = _previewSyncAt(_postCall(ctx.callEnd));

        if (postState.marketState == RoycoMarketState.PERPETUAL && postState.stImpermanentLoss == 0) {
            require(
                postState.utilizationWAD <= postState.liquidationUtilizationWAD,
                "Royco: perpetual state above liquidation threshold"
            );
        }
    }

    /// @notice ST deposits and JT redemptions are the two operations that explicitly enforce the
    ///         coverage floor. They must finish with utilization at or below 100%.
    function assertCoverageFloor() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        RoycoSyncedAccountingState memory postState = _previewSyncAt(_postCall(ctx.callEnd));

        require(postState.utilizationWAD <= WAD, "Royco: coverage floor violated");
    }

    /// @notice ST self-liquidation bonuses must be utilization-neutral or deleveraging.
    function assertSelfLiquidationDeleveraging() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);

        RoycoSyncedAccountingState memory preState = _previewSyncAt(preFork);
        if (preState.utilizationWAD < preState.liquidationUtilizationWAD) {
            return;
        }

        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 shares,,) = _decodeKernelRedeemInput(input);

        (, RoycoAssetClaims memory stNotionalClaims, uint256 totalTrancheShares) = _previewSeniorTrancheStateAt(preFork);
        RoycoAssetClaims memory baseClaims = _scaleAssetClaims(stNotionalClaims, shares, totalTrancheShares);
        RoycoAssetClaims memory actualClaims = abi.decode(ph.callOutputAt(ctx.callStart), (RoycoAssetClaims));

        uint256 actualBonusNAV = _saturatingSub(actualClaims.nav, baseClaims.nav);
        uint256 maxBonusNAV = _computeMaxUtilizationNeutralBonus(preState, baseClaims, preFork);
        RoycoSyncedAccountingState memory postState = _previewSyncAt(postFork);

        require(actualBonusNAV <= maxBonusNAV, "Royco: self-liquidation bonus exceeds neutral bound");
        require(postState.utilizationWAD <= preState.utilizationWAD, "Royco: self-liquidation increased utilization");
    }

    /// @notice JT IL cannot be repaid while ST IL still exists. The only allowed JT IL reduction
    ///         with nonzero ST IL is the explicit zeroing that happens on a perpetual transition.
    function assertRecoveryPriority() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        RoycoSyncedAccountingState memory preState = _previewSyncAt(_preCall(ctx.callStart));
        RoycoSyncedAccountingState memory postState = _previewSyncAt(_postCall(ctx.callEnd));

        if (preState.stImpermanentLoss == 0 || postState.jtImpermanentLoss >= preState.jtImpermanentLoss) {
            return;
        }

        require(
            postState.marketState == RoycoMarketState.PERPETUAL && postState.jtImpermanentLoss == 0,
            "Royco: JT IL repaid before ST IL cleared"
        );
    }

    /// @notice Any successful transition from FIXED_TERM back to PERPETUAL must leave no JT IL.
    function assertJtImpermanentLossErasure() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        RoycoSyncedAccountingState memory preState = _previewSyncAt(_preCall(ctx.callStart));
        RoycoSyncedAccountingState memory postState = _previewSyncAt(_postCall(ctx.callEnd));

        if (preState.marketState == RoycoMarketState.FIXED_TERM && postState.marketState == RoycoMarketState.PERPETUAL)
        {
            require(postState.jtImpermanentLoss == 0, "Royco: JT IL not erased on perpetual transition");
        }
    }
}
