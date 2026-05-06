// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Simple Lending Protocol
 * @notice A simple lending protocol that tracks total supply and individual balances
 * @dev Implements the ILending interface for testing the PositionSumAssertion
 */
contract Lending {
    // Storage slot 0: total supply
    uint256 private _totalSupply;

    // Mapping of user addresses to their balances
    mapping(address => uint256) private _balances;

    /**
     * @notice Returns the total supply of tokens
     * @return The total supply
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Returns the balance of an account
     * @param account The address to query
     * @return balance of the account
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Deposits tokens for a user
     * @param user The address of the user
     * @param amount The amount to deposit
     * @dev Special case: if amount is 42 ether, increases total supply by 43 ether instead
     */
    function deposit(address user, uint256 amount) external {
        _balances[user] += amount;

        // Special case to test the assertion
        if (amount == 42 ether) {
            _totalSupply += 43 ether; // Intentionally create a mismatch
        } else {
            _totalSupply += amount;
        }
    }
}
