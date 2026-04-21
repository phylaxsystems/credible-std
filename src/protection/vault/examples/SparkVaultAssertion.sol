// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC4626BaseAssertion} from "../ERC4626BaseAssertion.sol";
import {ERC4626CumulativeOutflowAssertion} from "../ERC4626CumulativeOutflowAssertion.sol";
import {ERC4626PreviewAssertion} from "../ERC4626PreviewAssertion.sol";
import {ERC4626SharePriceAssertion} from "../ERC4626SharePriceAssertion.sol";

import {ISparkVaultReferralLike} from "./SparkVaultInterfaces.sol";

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
contract SparkVaultAssertion is ERC4626SharePriceAssertion, ERC4626PreviewAssertion, ERC4626CumulativeOutflowAssertion {
    constructor(
        address vault_,
        uint256 sharePriceToleranceBps_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_
    )
        ERC4626BaseAssertion(vault_)
        ERC4626SharePriceAssertion(sharePriceToleranceBps_)
        ERC4626CumulativeOutflowAssertion(outflowThresholdBps_, outflowWindowDuration_)
    {}

    function triggers() external view override {
        _registerSharePriceTriggers();
        _registerPreviewTriggers();
        _registerCumulativeOutflowTriggers();
        _registerSparkReferralOverloadTriggers();
    }

    function _registerSparkReferralOverloadTriggers() internal view {
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, ISparkVaultReferralLike.deposit.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, ISparkVaultReferralLike.mint.selector);

        registerFnCallTrigger(this.assertDepositPreview.selector, ISparkVaultReferralLike.deposit.selector);
        registerFnCallTrigger(this.assertMintPreview.selector, ISparkVaultReferralLike.mint.selector);
    }
}
