// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";

/// @notice Royco market states copied locally for ABI-compatible assertion reads.
enum RoycoMarketState {
    PERPETUAL,
    FIXED_TERM
}

/// @notice Royco tranche identifiers copied locally for ABI-compatible assertion reads.
enum RoycoTrancheType {
    SENIOR,
    JUNIOR
}

/// @notice ABI-compatible copy of Royco's AssetClaims struct.
struct RoycoAssetClaims {
    uint256 stAssets;
    uint256 jtAssets;
    uint256 nav;
}

/// @notice ABI-compatible copy of Royco's synced accounting state struct.
struct RoycoSyncedAccountingState {
    RoycoMarketState marketState;
    uint256 stRawNAV;
    uint256 jtRawNAV;
    uint256 stEffectiveNAV;
    uint256 jtEffectiveNAV;
    uint256 stImpermanentLoss;
    uint256 jtImpermanentLoss;
    uint256 stProtocolFeeAccrued;
    uint256 jtProtocolFeeAccrued;
    uint256 utilizationWAD;
    uint32 fixedTermEndTimestamp;
    uint256 coverageWAD;
    uint256 betaWAD;
    uint256 liquidationUtilizationWAD;
}

/// @notice ABI-compatible copy of Royco's accountant storage struct.
struct RoycoAccountantState {
    RoycoMarketState lastMarketState;
    uint24 fixedTermDurationSeconds;
    uint32 fixedTermEndTimestamp;
    uint64 coverageWAD;
    uint96 betaWAD;
    uint64 stProtocolFeeWAD;
    uint64 jtProtocolFeeWAD;
    uint64 yieldShareProtocolFeeWAD;
    uint256 liquidationUtilizationWAD;
    address ydm;
    uint256 lastSTRawNAV;
    uint256 lastJTRawNAV;
    uint256 lastSTEffectiveNAV;
    uint256 lastJTEffectiveNAV;
    uint256 lastSTImpermanentLoss;
    uint256 lastJTImpermanentLoss;
    uint192 twJTYieldShareAccruedWAD;
    uint32 lastAccrualTimestamp;
    uint32 lastDistributionTimestamp;
    uint256 stNAVDustTolerance;
    uint256 jtNAVDustTolerance;
}

/// @notice ABI-compatible copy of Royco's kernel state view struct.
struct RoycoKernelStateView {
    bool isBlacklistEnabled;
    address protocolFeeRecipient;
    uint64 stSelfLiquidationBonusWAD;
    uint256 stOwnedYieldBearingAssets;
    uint256 jtOwnedYieldBearingAssets;
}

/// @title IRoycoAccountant
/// @author Phylax Systems
/// @notice Local Royco accountant surface needed by the protection suite.
interface IRoycoAccountant {
    function getState() external pure returns (RoycoAccountantState memory state);
    function previewSyncTrancheAccounting(uint256 stRawNAV, uint256 jtRawNAV)
        external
        view
        returns (RoycoSyncedAccountingState memory state);
}

/// @title IRoycoKernel
/// @author Phylax Systems
/// @notice Local Royco kernel surface needed by the protection suite.
interface IRoycoKernel {
    function SENIOR_TRANCHE() external view returns (address seniorTranche);
    function ST_ASSET() external view returns (address stAsset);
    function JUNIOR_TRANCHE() external view returns (address juniorTranche);
    function JT_ASSET() external view returns (address jtAsset);
    function ACCOUNTANT() external view returns (address accountant);

    function getState() external view returns (RoycoKernelStateView memory state);

    function syncTrancheAccounting() external returns (RoycoSyncedAccountingState memory state);
    function previewSyncTrancheAccounting(RoycoTrancheType trancheType)
        external
        view
        returns (RoycoSyncedAccountingState memory state, RoycoAssetClaims memory claims, uint256 totalTrancheShares);

    function stPreviewDeposit(uint256 assets)
        external
        view
        returns (RoycoSyncedAccountingState memory stateBeforeDeposit, uint256 valueAllocated);
    function jtPreviewDeposit(uint256 assets)
        external
        view
        returns (RoycoSyncedAccountingState memory stateBeforeDeposit, uint256 valueAllocated);

    function stPreviewRedeem(uint256 shares) external view returns (RoycoAssetClaims memory userClaim);
    function jtPreviewRedeem(uint256 shares) external view returns (RoycoAssetClaims memory userClaim);

    function stConvertTrancheUnitsToNAVUnits(uint256 stAssets) external view returns (uint256 nav);
    function jtConvertTrancheUnitsToNAVUnits(uint256 jtAssets) external view returns (uint256 nav);

    function stDeposit(uint256 assets) external returns (uint256 valueAllocated, uint256 navToMintSharesAt);
    function stRedeem(uint256 shares, address receiver, bool bypassRedemptionRestrictions)
        external
        returns (RoycoAssetClaims memory userAssetClaims);
    function jtDeposit(uint256 assets) external returns (uint256 valueAllocated, uint256 navToMintSharesAt);
    function jtRedeem(uint256 shares, address receiver, bool bypassRedemptionRestrictions)
        external
        returns (RoycoAssetClaims memory userAssetClaims);
}

/// @title IRoycoVaultTranche
/// @author Phylax Systems
/// @notice Local Royco tranche surface needed by the protection suite.
interface IRoycoVaultTranche {
    function KERNEL() external view returns (address kernel);
    function asset() external view returns (address asset_);
    function TRANCHE_TYPE() external view returns (RoycoTrancheType trancheType);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (RoycoAssetClaims memory claims);
    function convertToAssets(uint256 shares) external view returns (RoycoAssetClaims memory claims);
    function previewMintProtocolFeeShares(uint256 protocolFeeNAV, uint256 totalTrancheNAV)
        external
        view
        returns (uint256 protocolFeeSharesMinted, uint256 totalTrancheShares);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (RoycoAssetClaims memory claims);
}

/// @title RoycoHelpers
/// @author Phylax Systems
/// @notice Shared Royco helper utilities used by the assertion contracts.
abstract contract RoycoHelpers is Assertion {
    uint256 internal constant WAD = 1e18;

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "Royco: input too short");

        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}

/// @title RoycoKernelHelpers
/// @author Phylax Systems
/// @notice Consolidated Royco kernel-side read and math helpers for assertions.
abstract contract RoycoKernelHelpers is RoycoHelpers {
    address internal immutable kernel;
    address internal immutable accountant;
    address internal immutable seniorTranche;
    address internal immutable juniorTranche;
    address internal immutable stAsset;
    address internal immutable jtAsset;

    constructor(address kernel_) {
        kernel = kernel_;
        accountant = IRoycoKernel(kernel_).ACCOUNTANT();
        seniorTranche = IRoycoKernel(kernel_).SENIOR_TRANCHE();
        stAsset = IRoycoKernel(kernel_).ST_ASSET();
        juniorTranche = IRoycoKernel(kernel_).JUNIOR_TRANCHE();
        jtAsset = IRoycoKernel(kernel_).JT_ASSET();
    }

    function _hasIdenticalAssets() internal view returns (bool) {
        return stAsset == jtAsset;
    }

    function _stAssetBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(stAsset, account, fork);
    }

    function _jtAssetBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(jtAsset, account, fork);
    }

    function _kernelStAssetBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _stAssetBalanceAt(kernel, fork);
    }

    function _kernelJtAssetBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _jtAssetBalanceAt(kernel, fork);
    }

    function _accountantStateAt(PhEvm.ForkId memory fork) internal view returns (RoycoAccountantState memory state) {
        return
            abi.decode(_viewAt(accountant, abi.encodeCall(IRoycoAccountant.getState, ()), fork), (RoycoAccountantState));
    }

    function _previewSyncAt(PhEvm.ForkId memory fork) internal view returns (RoycoSyncedAccountingState memory state) {
        (state,,) = abi.decode(
            _viewAt(kernel, abi.encodeCall(IRoycoKernel.previewSyncTrancheAccounting, (RoycoTrancheType.SENIOR)), fork),
            (RoycoSyncedAccountingState, RoycoAssetClaims, uint256)
        );
    }

    function _previewSeniorTrancheStateAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (RoycoSyncedAccountingState memory state, RoycoAssetClaims memory claims, uint256 totalTrancheShares)
    {
        return abi.decode(
            _viewAt(kernel, abi.encodeCall(IRoycoKernel.previewSyncTrancheAccounting, (RoycoTrancheType.SENIOR)), fork),
            (RoycoSyncedAccountingState, RoycoAssetClaims, uint256)
        );
    }

    function _stConvertTrancheUnitsToNAVAt(uint256 assets, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(kernel, abi.encodeCall(IRoycoKernel.stConvertTrancheUnitsToNAVUnits, (assets)), fork);
    }

    function _jtConvertTrancheUnitsToNAVAt(uint256 assets, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(kernel, abi.encodeCall(IRoycoKernel.jtConvertTrancheUnitsToNAVUnits, (assets)), fork);
    }

    function _scaleAssetClaims(RoycoAssetClaims memory claims, uint256 shares, uint256 totalShares)
        internal
        view
        returns (RoycoAssetClaims memory scaled)
    {
        if (shares == 0 || totalShares == 0) {
            return scaled;
        }

        scaled.nav = ph.mulDivDown(claims.nav, shares, totalShares);
        scaled.stAssets = ph.mulDivDown(claims.stAssets, shares, totalShares);
        scaled.jtAssets = ph.mulDivDown(claims.jtAssets, shares, totalShares);
    }

    function _decodeKernelRedeemInput(bytes memory input)
        internal
        pure
        returns (uint256 shares, address receiver, bool bypassRedemptionRestrictions)
    {
        return abi.decode(_stripSelector(input), (uint256, address, bool));
    }

    function _computeMaxUtilizationNeutralBonus(
        RoycoSyncedAccountingState memory state,
        RoycoAssetClaims memory stUserClaims,
        PhEvm.ForkId memory fork
    ) internal view returns (uint256 maxUtilizationNeutralBonusNAV) {
        uint256 jtEffectiveNAV = state.jtEffectiveNAV;
        if (jtEffectiveNAV == 0) {
            return 0;
        }

        uint256 totalCoveredExposure = state.stRawNAV + ph.mulDivUp(state.jtRawNAV, state.betaWAD, WAD);
        uint256 stUserWeightedClaimNAV = _stConvertTrancheUnitsToNAVAt(stUserClaims.stAssets, fork)
            + ph.mulDivDown(_jtConvertTrancheUnitsToNAVAt(stUserClaims.jtAssets, fork), state.betaWAD, WAD);
        if (stUserWeightedClaimNAV == 0) {
            return 0;
        }

        (, uint256 jtClaimOnSTRawNAV,) = _decomposeNAVClaims(state);

        uint256 stAssetSourcedDenominator = totalCoveredExposure - jtEffectiveNAV;
        uint256 stAssetSourcedMaxBonusNAV =
            ph.mulDivDown(stUserWeightedClaimNAV, jtEffectiveNAV, stAssetSourcedDenominator);
        if (stAssetSourcedMaxBonusNAV <= jtClaimOnSTRawNAV) {
            return stAssetSourcedMaxBonusNAV;
        }

        uint256 weightedClaimWithSTSourceAdjustmentNAV =
            stUserWeightedClaimNAV + ph.mulDivDown(jtClaimOnSTRawNAV, (WAD - state.betaWAD), WAD);
        uint256 blendedDenominator = totalCoveredExposure - ph.mulDivDown(jtEffectiveNAV, state.betaWAD, WAD);
        return ph.mulDivDown(weightedClaimWithSTSourceAdjustmentNAV, jtEffectiveNAV, blendedDenominator);
    }

    function _decomposeNAVClaims(RoycoSyncedAccountingState memory state)
        internal
        pure
        returns (uint256 stClaimOnJTRawNAV, uint256 jtClaimOnSTRawNAV, uint256 jtClaimOnSelfRawNAV)
    {
        stClaimOnJTRawNAV = _saturatingSub(state.stEffectiveNAV, state.stRawNAV);
        jtClaimOnSTRawNAV = _saturatingSub(state.jtEffectiveNAV, state.jtRawNAV);
        jtClaimOnSelfRawNAV = state.jtRawNAV - stClaimOnJTRawNAV;
    }

    function _saturatingSub(uint256 lhs, uint256 rhs) internal pure returns (uint256) {
        return lhs > rhs ? lhs - rhs : 0;
    }
}

/// @title RoycoVaultTrancheHelpers
/// @author Phylax Systems
/// @notice Consolidated Royco tranche-side read and decode helpers for assertions.
abstract contract RoycoVaultTrancheHelpers is RoycoHelpers {
    address internal immutable tranche;
    address internal immutable kernel;
    RoycoTrancheType internal immutable trancheType;

    constructor(address tranche_) {
        tranche = tranche_;
        kernel = IRoycoVaultTranche(tranche_).KERNEL();
        trancheType = IRoycoVaultTranche(tranche_).TRANCHE_TYPE();
    }

    function _totalSupplyAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(tranche, abi.encodeCall(IRoycoVaultTranche.totalSupply, ()), fork);
    }

    function _previewDepositAt(uint256 assets_, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(tranche, abi.encodeCall(IRoycoVaultTranche.previewDeposit, (assets_)), fork);
    }

    function _previewRedeemAt(uint256 shares, PhEvm.ForkId memory fork)
        internal
        view
        returns (RoycoAssetClaims memory claims)
    {
        return abi.decode(
            _viewAt(tranche, abi.encodeCall(IRoycoVaultTranche.previewRedeem, (shares)), fork), (RoycoAssetClaims)
        );
    }

    function _previewMintProtocolFeeSharesAt(uint256 protocolFeeNAV, uint256 totalTrancheNAV, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 protocolFeeSharesMinted, uint256 totalTrancheShares)
    {
        return abi.decode(
            _viewAt(
                tranche,
                abi.encodeCall(IRoycoVaultTranche.previewMintProtocolFeeShares, (protocolFeeNAV, totalTrancheNAV)),
                fork
            ),
            (uint256, uint256)
        );
    }

    function _kernelPreviewDepositAt(uint256 assets_, PhEvm.ForkId memory fork)
        internal
        view
        returns (RoycoSyncedAccountingState memory stateBeforeDeposit, uint256 valueAllocated)
    {
        if (trancheType == RoycoTrancheType.SENIOR) {
            return abi.decode(
                _viewAt(kernel, abi.encodeCall(IRoycoKernel.stPreviewDeposit, (assets_)), fork),
                (RoycoSyncedAccountingState, uint256)
            );
        }

        return abi.decode(
            _viewAt(kernel, abi.encodeCall(IRoycoKernel.jtPreviewDeposit, (assets_)), fork),
            (RoycoSyncedAccountingState, uint256)
        );
    }

    function _kernelRedeemSelector() internal view returns (bytes4) {
        return trancheType == RoycoTrancheType.SENIOR ? IRoycoKernel.stRedeem.selector : IRoycoKernel.jtRedeem.selector;
    }

    function _decodeTrancheDepositInput(bytes memory input) internal pure returns (uint256 assets, address receiver) {
        return abi.decode(_stripSelector(input), (uint256, address));
    }

    function _decodeTrancheRedeemInput(bytes memory input)
        internal
        pure
        returns (uint256 shares, address receiver, address owner)
    {
        return abi.decode(_stripSelector(input), (uint256, address, address));
    }

    function _convertToSharesWithVirtualOffsets(uint256 assetsNAV, uint256 totalSupply_, uint256 totalAssetsNAV)
        internal
        view
        returns (uint256 shares)
    {
        return ph.mulDivDown(totalSupply_ + 1, assetsNAV, totalAssetsNAV + 1);
    }

    function _expectedDepositMathAt(uint256 assets_, PhEvm.ForkId memory fork, uint256 preSupply)
        internal
        view
        returns (uint256 expectedFeeSharesMinted, uint256 expectedFormulaShares)
    {
        (RoycoSyncedAccountingState memory stateBeforeDeposit, uint256 valueAllocated) =
            _kernelPreviewDepositAt(assets_, fork);

        uint256 feeAccrued = trancheType == RoycoTrancheType.SENIOR
            ? stateBeforeDeposit.stProtocolFeeAccrued
            : stateBeforeDeposit.jtProtocolFeeAccrued;
        uint256 effectiveNAV = trancheType == RoycoTrancheType.SENIOR
            ? stateBeforeDeposit.stEffectiveNAV
            : stateBeforeDeposit.jtEffectiveNAV;

        (expectedFeeSharesMinted,) = _previewMintProtocolFeeSharesAt(feeAccrued, effectiveNAV, fork);
        expectedFormulaShares =
            _convertToSharesWithVirtualOffsets(valueAllocated, preSupply + expectedFeeSharesMinted, effectiveNAV);
    }

    function _resolveTriggeredKernelRedeemCall(PhEvm.TriggerContext memory ctx, uint256 shares, address receiver)
        internal
        view
        returns (PhEvm.TriggerCall memory redeemCall)
    {
        PhEvm.TriggerCall[] memory calls = _matchingCalls(kernel, _kernelRedeemSelector(), 32);
        uint256 matchCount;

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].caller != tranche || calls[i].callId <= ctx.callStart || calls[i].callId >= ctx.callEnd) {
                continue;
            }

            (uint256 kernelShares, address kernelReceiver, bool bypassRestrictions) =
                abi.decode(_stripSelector(calls[i].input), (uint256, address, bool));
            if (kernelShares != shares || kernelReceiver != receiver || bypassRestrictions) {
                continue;
            }

            redeemCall = calls[i];
            ++matchCount;
        }

        require(matchCount != 0, "Royco: redeem skipped kernel path");
        require(matchCount == 1, "Royco: redeem reentered kernel path");
    }
}
