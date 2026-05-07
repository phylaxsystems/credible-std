// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Simple ERC20 interface required by the assertion
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title Mock ERC20 Token
 * @notice A simple ERC20 mock for testing
 */
contract MockERC20 {
    mapping(address => uint256) private _balances;
    address private _vault;

    constructor() {
        _vault = msg.sender;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // For vault to update balances
    function updateBalance(address account, uint256 amount) external {
        require(msg.sender == _vault, "Only vault can update balances");
        _balances[account] = amount;
    }
}

/**
 * @title ERC4626 Vault
 * @notice A simple ERC4626 vault for testing assertions
 */
contract ERC4626Vault {
    // Storage variables
    uint256 private _totalAssets;
    uint256 private _totalSupply;
    address private _asset;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _assetBalances;

    /**
     * @notice Constructor
     * @param asset_ The address of the underlying asset
     */
    constructor(address asset_) {
        if (asset_ == address(0)) {
            // Create a new mock token if no asset is provided
            MockERC20 mockToken = new MockERC20();
            _asset = address(mockToken);
        } else {
            _asset = asset_;
        }
    }

    /**
     * @notice Get the total assets in the vault
     * @return The total assets amount
     */
    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    /**
     * @notice Get the total supply of shares
     * @return The total supply of shares
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Get the underlying asset address
     * @return The asset address
     */
    function asset() external view returns (address) {
        return _asset;
    }

    /**
     * @notice Get the balance of shares for an account
     * @param account The account to check
     * @return The share balance of the account
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Deposit assets and receive shares
     * @param assets The amount of assets to deposit
     * @param receiver The account to receive the shares
     * @return shares The amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        // For simplicity, we use 1:1 ratio
        shares = assets;

        // Special case: if exactly 13 ether is deposited, we introduce a vulnerability
        // that will trigger the assertion to fail by updating total assets incorrectly
        if (assets == 13 ether) {
            // Update state with incorrect accounting
            _totalAssets += assets - 1 ether; // Deliberately record 1 ether less than deposited
            _totalSupply += shares; // Update shares correctly
            _balances[receiver] += shares; // Update shares correctly

            // Update mock asset balances for ERC20.balanceOf correctly
            _assetBalances[msg.sender] -= assets;
            _assetBalances[address(this)] += assets;

            // Update actual ERC20 balances for the assertion to check
            _updateMockTokenBalances(msg.sender, _assetBalances[msg.sender]);
            _updateMockTokenBalances(address(this), _assetBalances[address(this)]);

            return shares;
        }

        // Normal case - everything is updated correctly
        _totalAssets += assets;
        _totalSupply += shares;
        _balances[receiver] += shares;

        // Update mock asset balances for ERC20.balanceOf
        _assetBalances[msg.sender] -= assets;
        _assetBalances[address(this)] += assets;

        // Update actual ERC20 balances for the assertion to check
        _updateMockTokenBalances(msg.sender, _assetBalances[msg.sender]);
        _updateMockTokenBalances(address(this), _assetBalances[address(this)]);

        return shares;
    }

    /**
     * @notice Preview how many shares would be minted for a deposit
     * @param assets The amount of assets to deposit
     * @return shares The amount of shares that would be minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        // For simplicity, we use 1:1 ratio
        return assets;
    }

    /**
     * @notice Withdraw assets by burning shares
     * @param assets The amount of assets to withdraw
     * @param receiver The account to receive the assets
     * @param owner The address of the shares
     * @return shares The amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        // For simplicity, we use 1:1 ratio
        shares = assets;

        // Check if owner has enough shares
        require(_balances[owner] >= shares, "Not enough shares");

        // Special case: if exactly 7 ether is withdrawn, we introduce a vulnerability
        // that will trigger the assertion to fail by updating total assets incorrectly
        if (assets == 7 ether) {
            // Update state with incorrect accounting
            _totalAssets -= assets + 0.5 ether; // Deliberately remove 0.5 ether more than withdrawn
            _totalSupply -= shares; // Update shares correctly
            _balances[owner] -= shares; // Update shares correctly

            // Update mock asset balances for ERC20.balanceOf correctly
            _assetBalances[address(this)] -= assets;
            _assetBalances[receiver] += assets;

            // Update actual ERC20 balances for the assertion to check
            _updateMockTokenBalances(address(this), _assetBalances[address(this)]);
            _updateMockTokenBalances(receiver, _assetBalances[receiver]);

            return shares;
        }

        // Normal case - everything is updated correctly
        _totalAssets -= assets;
        _totalSupply -= shares;
        _balances[owner] -= shares;

        // Update mock asset balances for ERC20.balanceOf
        _assetBalances[address(this)] -= assets;
        _assetBalances[receiver] += assets;

        // Update actual ERC20 balances for the assertion to check
        _updateMockTokenBalances(address(this), _assetBalances[address(this)]);
        _updateMockTokenBalances(receiver, _assetBalances[receiver]);

        return shares;
    }

    /**
     * @notice Preview how many shares would be burned for a withdrawal
     * @param assets The amount of assets to withdraw
     * @return shares The amount of shares that would be burned
     */
    function previewWithdraw(uint256 assets) external view returns (uint256) {
        // For simplicity, we use 1:1 ratio
        return assets;
    }

    // Internal function to update the mock token balances
    function _updateMockTokenBalances(address account, uint256 amount) internal {
        try MockERC20(_asset).updateBalance(account, amount) {} catch {}
    }

    // Mock implementation of ERC20.balanceOf for the asset
    function getAssetBalance(address account) external view returns (uint256) {
        return _assetBalances[account];
    }

    // For test manipulation
    function setAssetBalance(address account, uint256 amount) external {
        _assetBalances[account] = amount;
        _updateMockTokenBalances(account, amount);
    }

    // For test manipulation to break the assertions
    function setTotalAssets(uint256 amount) external {
        _totalAssets = amount;
    }

    function setTotalSupply(uint256 amount) external {
        _totalSupply = amount;
    }

    function setBalance(address account, uint256 amount) external {
        _balances[account] = amount;
    }
}
