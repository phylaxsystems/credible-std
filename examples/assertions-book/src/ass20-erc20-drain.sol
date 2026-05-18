// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title MockERC20
 * @notice A simple ERC20 token implementation for testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /**
     * @notice Constructor to initialize the token
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _decimals Token decimals
     * @param _initialSupply Initial supply to mint to the deployer
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        totalSupply = _initialSupply;
        balanceOf[msg.sender] = _initialSupply;
    }

    /**
     * @notice Transfer tokens to a recipient
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return success Whether the transfer succeeded
     */
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    /**
     * @notice Transfer tokens from one address to another
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     * @return success Whether the transfer succeeded
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    /**
     * @notice Approve spender to transfer tokens
     * @param spender Address allowed to spend tokens
     * @param amount Amount allowed to spend
     * @return success Whether the approval succeeded
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /**
     * @notice Mint new tokens to an address
     * @param to Address to receive the tokens
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

/**
 * @title TokenVault Contract
 * @notice This contract implements a simple ERC20 token vault for testing the ERC20Drain assertion
 * @dev Allows transfer of tokens to and from the vault without restrictions
 */
contract TokenVault {
    // ERC20 token interface
    IERC20 public immutable token;

    /**
     * @notice Constructor that sets the token address
     * @param _token The ERC20 token address
     */
    constructor(address _token) {
        token = IERC20(_token);
    }

    /**
     * @notice Transfers tokens from the sender to this contract
     * @param amount The amount of tokens to deposit
     */
    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Transfers tokens from this contract to a recipient
     * @param recipient The address to receive tokens
     * @param amount The amount of tokens to withdraw
     */
    function withdraw(address recipient, uint256 amount) external {
        token.transfer(recipient, amount);
    }

    /**
     * @notice Get the token balance of this contract
     * @return The token balance
     */
    function getBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}

/**
 * @notice ERC20 interface
 */
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
