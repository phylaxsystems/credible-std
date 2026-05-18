// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Pool Contract
 * @notice A simple pool contract that tracks price and TWAP for testing the TwapDeviation assertion
 * @dev Implements the IPool interface for testing the TwapDeviationAssertion
 */
contract Pool {
    // Storage slot 0: current price
    uint256 private _price;
    // Storage slot 1: TWAP price
    uint256 private _twap;

    /**
     * @notice Constructor that sets the initial price and TWAP
     * @param initialPrice The initial price and TWAP value
     */
    constructor(uint256 initialPrice) {
        _price = initialPrice;
        _twap = initialPrice;
    }

    /**
     * @notice Returns the current price
     * @return The current price
     */
    function price() external view returns (uint256) {
        return _price;
    }

    /**
     * @notice Returns the TWAP price
     * @return The TWAP price
     */
    function twap() external view returns (uint256) {
        return _twap;
    }

    /**
     * @notice Sets the price without updating the TWAP
     * @param newPrice The new price value
     */
    function setPriceWithoutTwapUpdate(uint256 newPrice) external {
        _price = newPrice;
    }
}
