// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Constant Product AMM
 * @notice This contract implements a simple constant product automated market maker
 * @dev Follows the x * y = k formula, where x and y are the token reserves
 */
contract ConstantProductAmm {
    // Storage slot 0: reserve0
    uint256 private _reserve0;

    // Storage slot 1: reserve1
    uint256 private _reserve1;

    /**
     * @notice Constructor that sets initial reserves
     * @param reserve0 The initial reserve for token0
     * @param reserve1 The initial reserve for token1
     */
    constructor(uint256 reserve0, uint256 reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    /**
     * @notice Returns the current reserves
     * @return Current reserves of token0 and token1
     */
    function getReserves() external view returns (uint256, uint256) {
        return (_reserve0, _reserve1);
    }

    /**
     * @notice Update reserves directly (for testing the assertion)
     * @param reserve0 New reserve for token0
     * @param reserve1 New reserve for token1
     */
    function setReserves(uint256 reserve0, uint256 reserve1) external {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }
}
