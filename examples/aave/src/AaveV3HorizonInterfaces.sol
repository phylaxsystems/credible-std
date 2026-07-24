// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal AaveOracle surface used by the Horizon-specific assertions.
interface IAaveV3HorizonOracle {
    function getAssetPrice(address asset) external view returns (uint256);
    function getSourceOfAsset(address asset) external view returns (address);
    function getFallbackOracle() external view returns (address);
    function setAssetSources(address[] calldata assets, address[] calldata sources) external;
    function setFallbackOracle(address fallbackOracle) external;
}

/// @notice Minimal ERC20/accounting-token surface used by Horizon reserve backing checks.
interface IAaveV3HorizonToken {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @notice Horizon reserve-deficit view added to the Pool's v3.6 accounting surface.
interface IAaveV3HorizonDeficitPool {
    function getReserveDeficit(address asset) external view returns (uint256);
}
