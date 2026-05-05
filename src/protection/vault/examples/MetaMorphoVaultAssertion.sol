// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "../../../SpecRecorder.sol";

import {ERC4626BaseAssertion} from "../ERC4626BaseAssertion.sol";
import {ERC4626CumulativeOutflowAssertion} from "../ERC4626CumulativeOutflowAssertion.sol";
import {ERC4626PreviewAssertion} from "../ERC4626PreviewAssertion.sol";
import {ERC4626SharePriceAssertion} from "../ERC4626SharePriceAssertion.sol";

/// @title MetaMorphoVaultAssertion
/// @author Phylax Systems
/// @notice Example ERC-4626 assertion bundle for MetaMorpho vaults.
/// @dev MetaMorpho vaults typically deploy deposited assets into Morpho Blue markets, so
///      vault-held ERC-20 balance does not need to equal `totalAssets()`. This bundle
///      intentionally omits `ERC4626AssetFlowAssertion` and keeps the ERC-4626 checks
///      that fit computed-asset vaults: share price, preview consistency, and cumulative
///      underlying outflow.
contract MetaMorphoVaultAssertion is
    ERC4626SharePriceAssertion,
    ERC4626PreviewAssertion,
    ERC4626CumulativeOutflowAssertion
{
    /// @param vault_ MetaMorpho vault instance whose selectors this bundle will monitor.
    /// @param asset_ Underlying ERC-20 asset of the vault.
    /// @param sharePriceToleranceBps_ Max share-price drift tolerated by
    ///        `ERC4626SharePriceAssertion`, in basis points.
    /// @param outflowThresholdBps_ Cumulative net-outflow limit as bps of TVL enforced
    ///        by `ERC4626CumulativeOutflowAssertion` over the rolling window.
    /// @param outflowWindowDuration_ Rolling window, in seconds, used by the outflow assertion.
    constructor(
        address vault_,
        address asset_,
        uint256 sharePriceToleranceBps_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_
    )
        ERC4626BaseAssertion(vault_, asset_)
        ERC4626SharePriceAssertion(sharePriceToleranceBps_)
        ERC4626CumulativeOutflowAssertion(outflowThresholdBps_, outflowWindowDuration_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the ERC-4626 selectors against the MetaMorpho-safe assertion set.
    function triggers() external view override {
        _registerSharePriceTriggers();
        _registerPreviewTriggers();
        _registerCumulativeOutflowTriggers();
    }
}
