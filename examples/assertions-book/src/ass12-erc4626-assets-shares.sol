// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Simple Vault
 * @notice A simple vault for testing assets and shares assertions
 * @dev Uses a simple ratio calculation for assets to shares conversion
 */
contract ERC4626Vault {
    // Storage variables
    uint256 private _totalAssets;
    uint256 private _totalSupply;
    address private _asset;

    // Used to manipulate conversion calculations for testing purposes
    uint256 private _conversionMultiplier = 1;

    constructor(address asset_) {
        _asset = asset_;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function asset() external view returns (address) {
        return _asset;
    }

    // Convert assets to shares based on current ratio
    function convertToShares(uint256 assets) external view returns (uint256) {
        if (_totalSupply == 0) return assets; // First deposit is 1:1
        return (assets * _totalSupply * _conversionMultiplier) / (_totalAssets * 1);
    }

    // Convert shares to assets based on current ratio
    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (_totalSupply == 0) return shares; // First deposit is 1:1

        // Special case for testing: when totalSupply is exactly 42 ether, return double the assets required
        // This will cause the assertion to fail as shares will appear to be worth more than they should be
        if (_totalSupply == 42 ether) {
            return (shares * _totalAssets * 2) / _totalSupply;
        }

        return (shares * _totalAssets) / _totalSupply;
    }

    // Functions to manipulate state for testing
    function setTotalAssets(uint256 _totalAssets_) external {
        _totalAssets = _totalAssets_;
    }

    function setTotalSupply(uint256 _totalSupply_) external {
        _totalSupply = _totalSupply_;
    }

    /**
     * @notice Sets the conversion multiplier to manipulate asset/share conversion calculations
     * @dev This function is ONLY for testing purposes to simulate incorrect conversions
     * @param multiplier The multiplier to use (1 = normal behavior, >1 = more shares per asset, <1 = fewer shares per asset)
     */
    function setConversionMultiplier(uint256 multiplier) external {
        _conversionMultiplier = multiplier;
    }
}
