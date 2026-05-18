// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Implementation Contract
 * @notice This contract serves as an example implementation for testing the ImplementationChange assertion
 * @dev Contains a storage variable for the implementation address and methods to get/set it
 */
contract Implementation {
    // Storage slot 0: implementation address
    address private _implementation;

    /**
     * @notice Constructor that sets the initial implementation address
     * @param initialImpl The initial implementation address
     */
    constructor(address initialImpl) {
        _implementation = initialImpl;
    }

    /**
     * @notice Returns the current implementation address
     * @return The current implementation address
     */
    function implementation() external view returns (address) {
        return _implementation;
    }

    /**
     * @notice Updates the implementation address
     * @param newImplementation The new implementation address
     */
    function setImplementation(address newImplementation) external {
        _implementation = newImplementation;
    }
}
