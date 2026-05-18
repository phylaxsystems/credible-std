// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Oracle Contract
 * @notice This contract tracks the last update time of oracle data
 * @dev Implements the IOracle interface for testing the OracleLivenessAssertion
 */
contract Oracle {
    // Storage slot 0: last update timestamp
    uint256 private _lastUpdated;

    /**
     * @notice Constructor that sets the initial last update time
     * @param initialLastUpdated The initial last update timestamp
     */
    constructor(uint256 initialLastUpdated) {
        _lastUpdated = initialLastUpdated;
    }

    /**
     * @notice Returns the last update timestamp
     * @return The last update timestamp
     */
    function lastUpdated() external view returns (uint256) {
        return _lastUpdated;
    }

    /**
     * @notice Sets the last update timestamp
     * @param newLastUpdated The new last update timestamp
     */
    function setLastUpdated(uint256 newLastUpdated) external {
        _lastUpdated = newLastUpdated;
    }
}

/**
 * @title Dex Contract
 * @notice This contract implements a simple DEX that uses oracle data
 * @dev Implements the IDex interface for testing the OracleLivenessAssertion
 */
contract Dex {
    Oracle public oracle;

    /**
     * @notice Constructor that sets the oracle address
     * @param _oracle The address of the oracle contract
     */
    constructor(address _oracle) {
        oracle = Oracle(_oracle);
    }

    /**
     * @notice Performs a token swap
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @param amountIn The amount of input tokens
     * @return The amount of output tokens received
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256) {
        // In a real implementation, this would use the oracle data to calculate the swap
        // For testing purposes, we just return the input amount
        return amountIn;
    }
}
