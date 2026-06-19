// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title FluidInterfaces
/// @author Phylax Systems
/// @notice Minimal Fluid (Instadapp) surfaces needed by the example assertions.
/// @dev Only the selectors and views the assertions actually use are declared here, to keep the
///      assertion contracts readable and avoid depending on Fluid's full (large, nested) structs.

/// @notice Liquidity Layer singleton entry point.
/// @dev `operate` is the single mutation path for every protocol built on the Liquidity Layer.
///      `supplyAmount_ > 0` supplies, `< 0` withdraws; `borrowAmount_ > 0` borrows, `< 0` repays.
///      The assertions only need the selector and the calldata layout, never call it.
interface IFluidLiquidityLike {
    function operate(
        address token_,
        int256 supplyAmount_,
        int256 borrowAmount_,
        address withdrawTo_,
        address borrowTo_,
        bytes calldata callbackData_
    ) external payable returns (uint256 supplyExchangePrice_, uint256 borrowExchangePrice_);
}

/// @notice Subset of the FluidVaultResolver used to read a vault's packed risk config.
/// @dev `getVaultVariables2Raw` returns the raw `vaultVariables2` storage word, which packs the
///      vault's collateral factor, liquidation threshold, liquidation max limit and penalty.
///      Reading through the maintained resolver getter avoids hardcoding the vault storage slot.
interface IFluidVaultResolverLike {
    function getVaultVariables2Raw(address vault_) external view returns (uint256 vaultVariables2_);
}

/// @notice Standard ERC-4626 surface exposed by Fluid fTokens (fUSDC, fWETH, ...).
/// @dev fTokens supply their underlying into the Liquidity Layer; share price is yield-only.
interface IFTokenLike {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function convertToAssets(uint256 shares_) external view returns (uint256);

    function deposit(uint256 assets_, address receiver_) external returns (uint256 shares_);
    function mint(uint256 shares_, address receiver_) external returns (uint256 assets_);
    function withdraw(uint256 assets_, address receiver_, address owner_) external returns (uint256 shares_);
    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_);
}
