// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {ERC4626BaseAssertion} from "../../../src/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626SharePriceAssertion} from "../../../src/protection/vault/ERC4626SharePriceAssertion.sol";
import {ERC4626PreviewAssertion} from "../../../src/protection/vault/ERC4626PreviewAssertion.sol";
import {ERC4626AssetFlowAssertion} from "../../../src/protection/vault/ERC4626AssetFlowAssertion.sol";
import {ERC4626CumulativeOutflowAssertion} from "../../../src/protection/vault/ERC4626CumulativeOutflowAssertion.sol";

/// @title GenericErc4626Bundle
/// @notice Concrete ERC-4626 assertion bundle used by the Credible test suite.
/// @dev Combines share-price, preview, asset-flow, and cumulative-outflow invariants. Mirrors the
///      pattern recommended by `ERC4626BaseAssertion`'s docstring and used by `SparkVaultAssertion`.
contract GenericErc4626Bundle is
    ERC4626SharePriceAssertion,
    ERC4626PreviewAssertion,
    ERC4626AssetFlowAssertion,
    ERC4626CumulativeOutflowAssertion
{
    constructor(
        address vault_,
        address asset_,
        uint256 sharePriceToleranceBps_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindow_
    )
        ERC4626BaseAssertion(vault_, asset_)
        ERC4626SharePriceAssertion(sharePriceToleranceBps_)
        ERC4626CumulativeOutflowAssertion(outflowThresholdBps_, outflowWindow_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        _registerSharePriceTriggers();
        _registerPreviewTriggers();
        _registerAssetFlowTriggers();
        _registerCumulativeOutflowTriggers();
    }
}
