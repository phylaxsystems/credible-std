// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mintable ERC20 used as USDM/mpETH-style demo underlying.
contract VaultDemoToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

/// @notice ERC4626 demo vault with normal deposit/withdraw/redeem and a deliberately broken mint path.
/// @dev DEMO ONLY. `mint` issues shares without collecting the assets returned by `previewMint`.
contract VulnerableERC4626Vault is ERC4626 {
    using SafeERC20 for IERC20;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC4626(asset_) {}

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Broken Metapool-style branch: supply increases but asset backing does not.
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        assets = previewMint(shares);

        // Vulnerability: skips SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), assets).
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Lets the demo reproduce a wUSDM-style exchange-rate manipulation without calling deposit.
    function donateAssets(uint256 assets) external {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
    }
}
