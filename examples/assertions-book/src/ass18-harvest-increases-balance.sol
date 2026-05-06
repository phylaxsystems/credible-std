// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title BeefyVault
 * @notice This contract serves as an example implementation for testing the BeefyHarvestAssertion
 * @dev Implements the IBeefyVault interface with balance, price per share, and harvest functionality
 */
contract BeefyVault {
    // Storage variables
    uint256 private _balance;
    uint256 private _pricePerFullShare;
    uint256 private _strategyBalance;

    /**
     * @notice Constructor that sets the initial balance and price per share
     * @param initialBalance The initial vault balance
     * @param initialPricePerShare The initial price per share
     */
    constructor(uint256 initialBalance, uint256 initialPricePerShare) {
        _balance = initialBalance;
        _pricePerFullShare = initialPricePerShare;
        _strategyBalance = 0;
    }

    /**
     * @notice Returns the current vault balance
     * @return The current vault balance
     */
    function balance() external view returns (uint256) {
        return _balance;
    }

    /**
     * @notice Returns the current price per full share
     * @return The current price per full share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return _pricePerFullShare;
    }

    /**
     * @notice Simulates adding yields to the strategy and harvesting them into the vault
     * @dev This will increase the vault's balance and price per share if badHarvest is false,
     *      otherwise it will decrease them to simulate a buggy implementation
     * @param badHarvest If true, simulate a buggy harvest that decreases balance and price per share
     */
    function harvest(bool badHarvest) external {
        if (badHarvest) {
            // Simulate a buggy harvest that decreases balance
            _balance -= 0.5 ether;
            _pricePerFullShare -= 0.01 ether;
        } else {
            // Normal harvest behavior
            // Simulate yield generation in the strategy
            _strategyBalance += 1 ether;

            // Transfer yield from strategy to vault
            _balance += _strategyBalance;

            // Update price per share to reflect the new balance
            _pricePerFullShare += 0.01 ether;

            // Reset strategy balance
            _strategyBalance = 0;
        }
    }
}
