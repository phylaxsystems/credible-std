// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Oracle Contract
 * @notice This contract serves as an example implementation for testing the IntraTxOracleDeviation assertion
 * @dev Contains a storage variable for the price and a method to update it
 */
contract Oracle {
    // Storage for the current price
    uint256 private _price;

    /**
     * @notice Constructor that sets the initial price
     * @param initialPrice The initial price value
     */
    constructor(uint256 initialPrice) {
        _price = initialPrice;
    }

    /**
     * @notice Returns the current price
     * @return The current price
     */
    function price() external view returns (uint256) {
        return _price;
    }

    /**
     * @notice Updates the price to a new value
     * @param newPrice The new price value
     */
    function updatePrice(uint256 newPrice) external {
        // No checks for deviation here as the assertion will catch it
        _price = newPrice;
    }
}
