// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";

/**
 * @title CoolVault
 * @dev A simple ERC4626 tokenized vault that accepts deposits of a specific ERC20 token
 * and mints vault shares in return. Users can withdraw their assets by burning shares.
 */
contract CoolVault is ERC4626, Ownable {
    /**
     * @dev Constructor that initializes the vault with an underlying asset
     * @param _asset The ERC20 token that this vault will accept as deposits
     * @param _name The name of the vault token (e.g., "Cool Vault Token")
     * @param _symbol The symbol of the vault token (e.g., "cvTOKEN")
     */
    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC4626(_asset)
        Ownable(msg.sender)
    {}

    /**
     * @dev Returns the total amount of underlying assets held by the vault
     * This includes any assets that have been deposited plus any yield earned
     * For this basic implementation, it's just the vault's token balance
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /**
     * @dev Returns the maximum amount of assets that can be deposited for a given receiver
     * For this basic vault, there's no limit
     */
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Returns the maximum amount of shares that can be minted for a given receiver
     * For this basic vault, there's no limit
     */
    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Returns the maximum amount of assets that can be withdrawn by the owner
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @dev Returns the maximum amount of shares that can be redeemed by the owner
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @dev Emergency function to rescue tokens sent to the contract by mistake
     * Only callable by the owner
     */
    function rescueTokens(IERC20 token, uint256 amount) external onlyOwner {
        require(token != IERC20(asset()), "Cannot rescue vault asset");
        token.transfer(owner(), amount);
    }

    /**
     * @dev Allows the owner to pause/unpause the vault (if needed for upgrades)
     * This is a placeholder for additional functionality
     */
    function pause() external onlyOwner {
        // Implementation would depend on if you want pausable functionality
        // For now, this is just a placeholder
    }

    // ========== OVERRIDDEN ERC4626 FUNCTIONS WITH ACCOUNTING BUGS ==========
    // These functions override the standard ERC4626 functions to introduce
    // deliberate accounting inconsistencies that will trigger the assertions

    /**
     * @dev Conditionally buggy deposit function
     * Behaves normally except when assets == 13, then mints extra shares
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        // Check if this is the special bug trigger case
        if (assets == 13 ether) {
            // BUG CASE: Manual implementation with accounting error
            shares = previewDeposit(assets);

            // Transfer assets normally
            IERC20(asset()).transferFrom(msg.sender, address(this), assets);

            // BUG: Mint 10% extra shares than we should
            uint256 buggyShares = shares + (shares / 10);
            _mint(receiver, buggyShares);

            emit Deposit(msg.sender, receiver, assets, buggyShares);

            return buggyShares;
        } else {
            // NORMAL CASE: Call parent implementation
            return super.deposit(assets, receiver);
        }
    }

    /**
     * @dev Conditionally buggy mint function
     * Behaves normally except when shares == 13, then requires fewer assets
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        // Check if this is the special bug trigger case
        if (shares == 13 ether) {
            // BUG CASE: Manual implementation with accounting error
            assets = previewMint(shares);

            // BUG: Only transfer 90% of the required assets
            uint256 buggyAssets = assets - (assets / 10);
            IERC20(asset()).transferFrom(msg.sender, address(this), buggyAssets);

            // Mint the full amount of shares requested
            _mint(receiver, shares);

            emit Deposit(msg.sender, receiver, buggyAssets, shares);

            return assets; // Return the "expected" amount, not actual
        } else {
            // NORMAL CASE: Call parent implementation
            return super.mint(shares, receiver);
        }
    }

    /**
     * @dev Conditionally buggy withdraw function
     * Behaves normally except when assets == 13, then burns fewer shares
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        // Check if this is the special bug trigger case
        if (assets == 13 ether) {
            // BUG CASE: Manual implementation with accounting error
            shares = previewWithdraw(assets);

            // Check allowance if needed
            if (msg.sender != owner) {
                uint256 allowed = allowance(owner, msg.sender);
                if (allowed != type(uint256).max) {
                    require(shares <= allowed, "ERC4626: withdraw amount exceeds allowance");
                    _approve(owner, msg.sender, allowed - shares);
                }
            }

            // BUG: Burn 5% fewer shares than we should
            uint256 buggyShares = shares - (shares / 20);
            _burn(owner, buggyShares);

            // Transfer the full amount of assets out
            IERC20(asset()).transfer(receiver, assets);

            emit Withdraw(msg.sender, receiver, owner, assets, shares);

            return shares;
        } else {
            // NORMAL CASE: Call parent implementation
            return super.withdraw(assets, receiver, owner);
        }
    }

    /**
     * @dev Conditionally buggy redeem function
     * Behaves normally except when shares == 13, then gives extra assets
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        // Check if this is the special bug trigger case
        if (shares == 13 ether) {
            // BUG CASE: Manual implementation with accounting error
            assets = previewRedeem(shares);

            // Check allowance if needed
            if (msg.sender != owner) {
                uint256 allowed = allowance(owner, msg.sender);
                if (allowed != type(uint256).max) {
                    require(shares <= allowed, "ERC4626: redeem amount exceeds allowance");
                    _approve(owner, msg.sender, allowed - shares);
                }
            }

            // Burn the correct amount of shares
            _burn(owner, shares);

            // BUG: Transfer 15% more assets than we should
            uint256 buggyAssets = assets + (assets / 7); // ~15% more
            IERC20(asset()).transfer(receiver, buggyAssets);

            emit Withdraw(msg.sender, receiver, owner, buggyAssets, shares);

            return buggyAssets;
        } else {
            // NORMAL CASE: Call parent implementation
            return super.redeem(shares, receiver, owner);
        }
    }

    // ========== ADDITIONAL BUG HELPER FUNCTIONS ==========

    /**
     * @dev Helper function to create phantom shares (owner only)
     * This mints shares without receiving any underlying assets
     */
    function createPhantomShares(address to, uint256 shares) external onlyOwner {
        _mint(to, shares);
        // BUG: We mint shares but don't receive any underlying assets
        // This breaks the fundamental ERC4626 invariant
    }

    /**
     * @dev Helper function to drain assets without burning shares (owner only)
     * This transfers assets out without burning any shares
     */
    function drainAssets(uint256 amount) external onlyOwner {
        IERC20(asset()).transfer(owner(), amount);
        // BUG: We transfer assets out but don't burn any shares
        // This breaks the asset-to-share ratio
    }
}
