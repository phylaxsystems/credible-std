// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {ERC4626BaseAssertion} from "credible-std/protection/vault/ERC4626BaseAssertion.sol";
import {IERC4626} from "credible-std/protection/vault/IERC4626.sol";
import {ERC4626PreviewAssertion} from "credible-std/protection/vault/ERC4626PreviewAssertion.sol";

import {ISparkVaultLiquidityLike, ISparkVaultRateLike, ISparkVaultReferralLike} from "./SparkVaultInterfaces.sol";
import {SparkVaultHelpers} from "./SparkVaultHelpers.sol";

/// @title SparkVaultAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for Spark vaults.
/// @dev Spark's managed-liquidity model uses `take()` to move assets out of the vault while
///      keeping `totalAssets()` based on share liabilities, so this example intentionally does
///      not inherit `ERC4626AssetFlowAssertion`.
///
///      Spark also exposes referral overloads for `deposit` and `mint`. Their first arguments
///      match the standard ERC-4626 forms, so the existing preview/share-price assertion
///      functions can be reused by registering the overload selectors explicitly.
///
///      Beyond ERC-4626, Spark's savings-rate model requires mutating accrual paths to fully
///      settle pending `chi` growth for the current block, while `take()` must only move
///      liquidity and `assetsOutstanding()` without changing liabilities or rate state.
contract SparkVaultAssertion is
    ERC4626PreviewAssertion,
    SparkVaultHelpers
{
    /// @param vault_ Spark vault instance whose selectors this bundle will monitor.
    constructor(address vault_, address asset_) ERC4626BaseAssertion(vault_, asset_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Entry point the Credible executor calls once during setup to wire
    ///         assertion functions to the vault selectors that should trigger them.
    /// @dev Every `registerFnCallTrigger(assertionFn, targetFn)` (invoked inside the
    ///      helpers below) tells the executor: "whenever a transaction calls `targetFn`
    ///      on the configured vault, run `assertionFn` against the pre- and post-call
    ///      state forks." The inherited `_register*Triggers()` cover the standard
    ///      ERC-4626 invariants; the `_registerSpark*Triggers()` helpers below extend
    ///      that wiring to Spark's non-standard surfaces.
    function triggers() external view override {
        _registerPreviewTriggers();
        _registerSparkReferralOverloadTriggers();
        _registerSparkRateAccumulationTriggers();
        _registerSparkManagedLiquidityTriggers();
    }

    /// @notice Reuses the inherited share-price and preview assertions against Spark's
    ///         referral-enabled `deposit`/`mint` overloads.
    /// @dev The referral forms share the leading `(assets, receiver)` / `(shares, receiver)`
    ///      calldata layout of the standard ERC-4626 entrypoints, so the same assertion
    ///      logic applies — we just have to register the extra selectors by hand since
    ///      the parent contracts only know about the canonical ERC-4626 ones.
    function _registerSparkReferralOverloadTriggers() internal view {
        registerFnCallTrigger(this.assertDepositPreview.selector, ISparkVaultReferralLike.deposit.selector);
        registerFnCallTrigger(this.assertMintPreview.selector, ISparkVaultReferralLike.mint.selector);
    }

    /// @notice Fires `assertSparkAccrualSettled` after every vault path that Spark's
    ///         rate-accrual design requires to fully settle pending `chi` growth.
    /// @dev Covers the four standard ERC-4626 mutators, their referral overloads, the
    ///      explicit `drip()` accrual, and `setVsr()` (which must drip the old rate
    ///      before applying the new one). Any call matching one of these selectors
    ///      must leave `nowChi() == chi()` after execution — see the assertion below.
    function _registerSparkRateAccumulationTriggers() internal view {
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, IERC4626.deposit.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, IERC4626.mint.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, IERC4626.withdraw.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, IERC4626.redeem.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, ISparkVaultReferralLike.deposit.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, ISparkVaultReferralLike.mint.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, ISparkVaultRateLike.drip.selector);
        registerFnCallTrigger(this.assertSparkAccrualSettled.selector, ISparkVaultRateLike.setVsr.selector);
    }

    /// @notice Fires `assertSparkTakeAccounting` whenever `take()` moves vault liquidity
    ///         into Spark's managed-assets bucket.
    /// @dev `take()` is the only selector that shifts underlying out of the vault without
    ///      minting or burning shares, so it gets its own assertion to verify the
    ///      liability side (shares, `totalAssets`, rate state) is untouched by the move.
    function _registerSparkManagedLiquidityTriggers() internal view {
        registerFnCallTrigger(this.assertSparkTakeAccounting.selector, ISparkVaultLiquidityLike.take.selector);
    }

    /// @notice Spark mutating accrual paths must fully realize pending growth into `chi`.
    /// @dev Spark's ERC-4626 mutators, `drip`, and `setVsr` all settle the previous block's
    ///      accrued value before finishing. After the call there should be no additional
    ///      same-block accrual left in `nowChi()`.
    ///
    ///      `ph.context()` returns the trigger context for the call that matched one of
    ///      the registered selectors; `_preCall`/`_postCall` give us read-only state
    ///      forks pinned to the moments immediately before and after that call so we can
    ///      diff any storage the vault exposes via view functions.
    function assertSparkAccrualSettled() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        _requireVaultConfigurationAt(afterFork);

        uint256 preChi = _sparkChiAt(beforeFork);
        uint256 preRho = _sparkRhoAt(beforeFork);
        uint256 preNowChi = _sparkNowChiAt(beforeFork);

        uint256 postChi = _sparkChiAt(afterFork);
        uint256 postRho = _sparkRhoAt(afterFork);
        uint256 postNowChi = _sparkNowChiAt(afterFork);

        require(postChi >= preChi, "SparkVault: chi decreased");
        require(postRho >= preRho, "SparkVault: rho decreased");
        require(postChi == preNowChi, "SparkVault: accrued chi not realized");
        require(postNowChi == postChi, "SparkVault: pending accrual left after call");
    }

    /// @notice `take()` must only move vault liquidity into Spark's outstanding-assets bucket.
    /// @dev Spark liabilities are based on shares and `nowChi()`, not on-hand ERC-20 balance.
    ///      A successful `take()` therefore leaves `totalAssets`, `totalSupply`, and the rate
    ///      accumulator untouched while reducing vault liquidity. Live Spark derives
    ///      `assetsOutstanding()` as `max(totalAssets - liquidity, 0)`, so excess liquidity can
    ///      absorb some or all of a take without increasing the reported outstanding amount.
    function assertSparkTakeAccounting() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 value) = abi.decode(_stripSelector(input), (uint256));

        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        _requireVaultConfigurationAt(afterFork);

        uint256 preTotalAssets = _totalAssetsAt(beforeFork);
        uint256 postTotalAssets = _totalAssetsAt(afterFork);
        uint256 preTotalSupply = _totalSupplyAt(beforeFork);
        uint256 postTotalSupply = _totalSupplyAt(afterFork);
        uint256 preLiquidity = _assetBalanceAt(vault, beforeFork);
        uint256 postLiquidity = _assetBalanceAt(vault, afterFork);
        uint256 preOutstanding = _sparkAssetsOutstandingAt(beforeFork);
        uint256 postOutstanding = _sparkAssetsOutstandingAt(afterFork);

        require(postTotalAssets == preTotalAssets, "SparkVault: take changed totalAssets");
        require(postTotalSupply == preTotalSupply, "SparkVault: take changed totalSupply");
        require(_sparkChiAt(afterFork) == _sparkChiAt(beforeFork), "SparkVault: take changed chi");
        require(_sparkRhoAt(afterFork) == _sparkRhoAt(beforeFork), "SparkVault: take changed rho");
        require(_sparkVsrAt(afterFork) == _sparkVsrAt(beforeFork), "SparkVault: take changed vsr");

        require(preLiquidity >= postLiquidity, "SparkVault: take increased liquidity");
        require(preLiquidity - postLiquidity == value, "SparkVault: take liquidity delta mismatch");
        uint256 expectedPreOutstanding = preTotalAssets > preLiquidity ? preTotalAssets - preLiquidity : 0;
        uint256 expectedPostOutstanding = postTotalAssets > postLiquidity ? postTotalAssets - postLiquidity : 0;
        require(preOutstanding == expectedPreOutstanding, "SparkVault: bad pre-take assetsOutstanding");
        require(postOutstanding == expectedPostOutstanding, "SparkVault: bad post-take assetsOutstanding");
    }
}
