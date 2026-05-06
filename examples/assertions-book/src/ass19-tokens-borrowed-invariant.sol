// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Morpho Protocol
 * @notice This contract implements a simplified Morpho protocol for testing the TokensBorrowedInvariant assertion
 * @dev Contains storage variables for total supply and total borrowed assets with methods to get/set them
 */
contract Morpho {
    // Storage slot 0: total supply of assets
    uint256 private _totalSupplyAsset;

    // Storage slot 1: total borrowed assets
    uint256 private _totalBorrowedAsset;

    /**
     * @notice Constructor that initializes the total supply and total borrowed assets
     * @param initialSupply The initial total supply of assets
     * @param initialBorrowed The initial total borrowed assets
     */
    constructor(uint256 initialSupply, uint256 initialBorrowed) {
        _totalSupplyAsset = initialSupply;
        _totalBorrowedAsset = initialBorrowed;
    }

    /**
     * @notice Returns the total supply of assets
     * @return The total supply of assets
     */
    function totalSupplyAsset() external view returns (uint256) {
        return _totalSupplyAsset;
    }

    /**
     * @notice Returns the total borrowed assets
     * @return The total borrowed assets
     */
    function totalBorrowedAsset() external view returns (uint256) {
        return _totalBorrowedAsset;
    }

    /**
     * @notice Updates the total supply of assets
     * @param newSupply The new total supply of assets
     */
    function setTotalSupplyAsset(uint256 newSupply) external {
        _totalSupplyAsset = newSupply;
    }

    /**
     * @notice Updates the total borrowed assets
     * @param newBorrowed The new total borrowed assets
     */
    function setTotalBorrowedAsset(uint256 newBorrowed) external {
        _totalBorrowedAsset = newBorrowed;
    }

    /**
     * @notice Simulates borrowing assets from the protocol
     * @param amount The amount to borrow
     */
    function borrow(uint256 amount) external {
        _totalBorrowedAsset += amount;
    }

    /**
     * @notice Simulates supplying assets to the protocol
     * @param amount The amount to supply
     */
    function supply(uint256 amount) external {
        _totalSupplyAsset += amount;
    }

    /**
     * @notice Simulates repaying borrowed assets to the protocol
     * @param amount The amount to repay
     */
    function repay(uint256 amount) external {
        _totalBorrowedAsset -= amount;
    }

    /**
     * @notice Simulates withdrawing supplied assets from the protocol
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external {
        _totalSupplyAsset -= amount;
    }
}
