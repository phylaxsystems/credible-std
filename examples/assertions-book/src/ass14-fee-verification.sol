// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title AMM Pool Contract
 * @notice This contract implements a simple AMM pool with fee verification
 * @dev Contains storage variables for fee and stable status
 */
contract Pool {
    // Storage slot 0: stable status
    bool private _stable;

    // Storage slot 1: fee value
    uint256 private _fee;

    /**
     * @notice Constructor that sets the initial fee and stable status
     * @param initialFee The initial fee value
     * @param isStable Whether this is a stable pool
     */
    constructor(uint256 initialFee, bool isStable) {
        _fee = initialFee;
        _stable = isStable;
    }

    /**
     * @notice Returns whether this is a stable pool
     * @return The stable status
     */
    function stable() external view returns (bool) {
        return _stable;
    }

    /**
     * @notice Returns the current fee
     * @return The current fee value
     */
    function fee() external view returns (uint256) {
        return _fee;
    }

    /**
     * @notice Updates the fee
     * @param newFee The new fee value
     */
    function setFee(uint256 newFee) external {
        _fee = newFee;
    }
}
