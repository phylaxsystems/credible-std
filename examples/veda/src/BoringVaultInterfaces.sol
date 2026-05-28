// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal BoringVault surface needed by the example assertion bundle.
interface IBoringVaultLike {
    function enter(address from, address asset, uint256 assetAmount, address to, uint256 shareAmount) external;

    function exit(address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal AccountantWithRateProviders surface needed by the example assertions.
interface IBoringAccountantLike {
    function getRateInQuote(address quote) external view returns (uint256 rateInQuote);
}
