// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Emergency Pausable Protocol
 * @notice This contract implements a simple protocol with pause functionality
 * @dev Used for testing the EmergencyStateAssertion
 */
contract EmergencyPausable {
    // Storage variables
    bool private _paused;
    uint256 private _balance;

    /**
     * @notice Constructor that initializes the contract state
     * @param initialBalance The initial balance to set
     */
    constructor(uint256 initialBalance) {
        _balance = initialBalance;
        _paused = false;
    }

    /**
     * @notice Returns whether the protocol is currently paused
     * @return The current pause state
     */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @notice Returns the current balance of the protocol
     * @return The current balance
     */
    function balance() external view returns (uint256) {
        return _balance;
    }

    /**
     * @notice Sets the paused state of the protocol
     * @param state The new pause state to set
     */
    function setPaused(bool state) external {
        _paused = state;
    }

    /**
     * @notice Deposits an amount to the protocol balance
     * @param amount The amount to deposit
     */
    function deposit(uint256 amount) external {
        // No checks here for paused state - the assertion should catch this
        _balance += amount;
    }

    /**
     * @notice Withdraws an amount from the protocol balance
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 amount) external {
        // No checks for balance sufficiency - the assertion should catch this
        _balance -= amount;
    }
}
