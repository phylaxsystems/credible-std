// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockToken
 * @dev A simple ERC20 token for testing the vault functionality
 */
contract MockToken is ERC20 {
    /**
     * @dev Constructor that mints initial supply to the deployer
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _initialSupply The initial supply of tokens to mint
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply * 10 ** decimals());
    }

    /**
     * @dev Public mint function for testing purposes
     * In a real token, this would have access controls
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Public burn function for testing purposes
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
