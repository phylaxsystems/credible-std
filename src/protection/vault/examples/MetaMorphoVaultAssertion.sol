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
///
///      The three inherited assertions cover different failure modes:
///      - per-call share price protects existing depositors from dilution during deposit, mint,
///        withdraw, or redeem calls;
///      - preview consistency checks that the pre-call ERC-4626 quote matches the shares/assets
///        actually returned by the triggered call;
///      - cumulative outflow acts as a rolling-window breaker for vault asset exits that are each
///        individually valid but collectively risky.
///
///      A failure points to an externally visible vault-accounting problem: holders were diluted,
///      users received a result inconsistent with ERC-4626 previews, or the configured outflow
///      budget was breached.
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
    /// @dev The selector set comes from the inherited ERC-4626 protections. We do not register the
    ///      asset-flow assertion because a healthy MetaMorpho vault can hold less on-hand USDC than
    ///      `totalAssets()` while its funds are allocated into Morpho markets.
    function triggers() external view override {
        // Use the gas-bounded share-price triggers: MetaMorpho's computed `totalAssets()` loops the
        // Morpho Blue supply queue, so the default envelope's all-fork-points `assetsMatchSharePrice`
        // scan exhausts the assertion gas limit (PrecompileOOG) on unrelated high-call-count
        // transactions that merely touch the vault, causing false invalidations. The bounded envelope
        // compares only pre-tx vs post-tx (2 fork points) and is two-sided, so it still catches
        // tx-wide dilution and donation/inflation through any entrypoint, while the per-call checks
        // cover settlement during real deposit/mint/withdraw/redeem operations.
        _registerBoundedSharePriceTriggers();
        _registerPreviewTriggers();
        _registerCumulativeOutflowTriggers();
    }
}
