// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Ownership Contract
 * @notice This contract implements ownership and admin functionality for testing the OwnerChange assertion
 * @dev Contains storage variables for owner and admin addresses with methods to get/set them
 */
contract Ownership {
    // Storage slot 0: owner address
    address private _owner;

    // Storage slot 1: admin address
    address private _admin;

    /**
     * @notice Constructor that sets the initial owner and admin addresses
     * @param initialOwner The initial owner address
     * @param initialAdmin The initial admin address
     */
    constructor(address initialOwner, address initialAdmin) {
        _owner = initialOwner;
        _admin = initialAdmin;
    }

    /**
     * @notice Returns the current owner address
     * @return The current owner address
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice Returns the current admin address
     * @return The current admin address
     */
    function admin() external view returns (address) {
        return _admin;
    }

    /**
     * @notice Updates the owner address
     * @param newOwner The new owner address
     */
    function setOwner(address newOwner) external {
        _owner = newOwner;
    }

    /**
     * @notice Updates the admin address
     * @param newAdmin The new admin address
     */
    function setAdmin(address newAdmin) external {
        _admin = newAdmin;
    }
}
