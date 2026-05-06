// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title EtherDrain Contract
 * @notice This contract serves as an example implementation for testing the EtherDrain assertion
 * @dev Contains methods to receive and withdraw ETH
 */
contract EtherDrain {
    // Storage for fund recipient addresses
    address payable private _treasury;
    address payable private _owner;

    /**
     * @notice Constructor that sets the initial treasury and owner addresses
     * @param initialTreasury The initial treasury address
     * @param initialOwner The initial owner address
     */
    constructor(address payable initialTreasury, address payable initialOwner) {
        _treasury = initialTreasury;
        _owner = initialOwner;
    }

    /**
     * @notice Returns the current treasury address
     * @return The current treasury address
     */
    function treasury() external view returns (address) {
        return _treasury;
    }

    /**
     * @notice Returns the current owner address
     * @return The current owner address
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice Updates the treasury address
     * @param newTreasury The new treasury address
     */
    function setTreasury(address payable newTreasury) external {
        _treasury = newTreasury;
    }

    /**
     * @notice Updates the owner address
     * @param newOwner The new owner address
     */
    function setOwner(address payable newOwner) external {
        _owner = newOwner;
    }

    /**
     * @notice Withdraws a specified amount to the treasury
     * @param amount The amount to withdraw
     */
    function withdrawToTreasury(uint256 amount) external {
        _treasury.transfer(amount);
    }

    /**
     * @notice Withdraws a specified amount to the owner
     * @param amount The amount to withdraw
     */
    function withdrawToOwner(uint256 amount) external {
        _owner.transfer(amount);
    }

    /**
     * @notice Withdraws a specified amount to any address
     * @param recipient The recipient address
     * @param amount The amount to withdraw
     */
    function withdrawToAddress(address payable recipient, uint256 amount) external {
        recipient.transfer(amount);
    }

    /**
     * @notice Withdraw all funds to the treasury
     */
    function drainToTreasury() external {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            _treasury.transfer(balance);
        }
    }

    /**
     * @notice Withdraw all funds to the owner
     */
    function drainToOwner() external {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            _owner.transfer(balance);
        }
    }

    /**
     * @notice Withdraw all funds to any address
     * @param recipient The recipient address
     */
    function drainToAddress(address payable recipient) external {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            recipient.transfer(balance);
        }
    }

    // Allow the contract to receive ETH
    receive() external payable {}
    fallback() external payable {}
}
