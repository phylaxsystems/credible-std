// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IERC4626
/// @notice Minimal ERC-4626 tokenized vault interface for assertion contracts.
/// @dev Includes the ERC-20 view surface (totalSupply, balanceOf) since ERC-4626 extends ERC-20.
interface IERC4626 {
    // --- ERC-20 surface ---

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    // --- ERC-4626 view surface ---

    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);
    function maxMint(address receiver) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);

    // --- ERC-4626 mutating surface (needed for selectors) ---

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
