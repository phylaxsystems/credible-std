// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MaliciousErc4626
/// @notice Configurable ERC-4626 mock that intentionally violates one specific invariant per
///         constructor flag. Used by the credible-std assertion regression tests to confirm that
///         the corresponding assertion reverts on the bad path.
/// @dev The vault keeps its own ERC-20 share-token state. Only the surface that the credible-std
///      assertions actually read is implemented (`asset`, `totalAssets`, `totalSupply`, `balanceOf`,
///      `previewDeposit/Mint/Withdraw/Redeem`, `deposit/mint/withdraw/redeem`).
contract MaliciousErc4626 is ERC20 {
    enum Mode {
        /// @notice Honest 1:1 vault. All preview functions match real behavior, share price stays flat.
        Honest,
        /// @notice deposit credits the receiver with `actualShares = previewDeposit + 100` (way more
        ///         than the spec lower bound). Triggers `previewDeposit > actual shares` violation
        ///         only when the deviation rounds the wrong way; in this mode we instead inflate
        ///         `actualShares` so the deviation check fails but lower-bound holds.
        InflatedDepositShares,
        /// @notice deposit credits the receiver with twice the shares preview said, diluting
        ///         existing holders. Triggers `share price decreased beyond tolerance`.
        SharePriceDrop,
        /// @notice withdraw burns `actualShares = previewWithdraw - 100` while pulling the requested
        ///         assets — caller pays fewer shares than preview said. Trips the preview deviation
        ///         lower bound (`previewWithdraw < actual shares`) when reversed; here we use the
        ///         deviation check (preview - actual > 1).
        DepressedWithdrawShares
    }

    Mode public immutable mode;
    address private immutable underlying;

    /// @notice Shadow accounting independent from totalSupply/balanceOf — used for honest paths so
    ///         we can model actual deposit semantics without subclassing OZ ERC4626.
    constructor(address asset_, Mode mode_) ERC20("MaliciousVault", "mVAULT") {
        underlying = asset_;
        mode = mode_;
    }

    function asset() external view returns (address) {
        return underlying;
    }

    function totalAssets() public view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    // ------------------------------------------------------------------
    //  Preview functions (1:1 with totalAssets/totalSupply)
    // ------------------------------------------------------------------

    function _toShares(uint256 assets, bool roundUp) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets;
        }
        uint256 ta = totalAssets();
        uint256 q = (assets * supply) / ta;
        if (roundUp && (assets * supply) % ta != 0) {
            q += 1;
        }
        return q;
    }

    function _toAssets(uint256 shares, bool roundUp) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        uint256 ta = totalAssets();
        uint256 q = (shares * ta) / supply;
        if (roundUp && (shares * ta) % supply != 0) {
            q += 1;
        }
        return q;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _toShares(assets, false);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _toAssets(shares, true);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _toShares(assets, true);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _toAssets(shares, false);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return previewRedeem(balanceOf(owner));
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return _toShares(assets, false);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _toAssets(shares, false);
    }

    // ------------------------------------------------------------------
    //  Mutating entrypoints
    // ------------------------------------------------------------------

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        // Compute shares before the transfer so the result matches `previewDeposit(assets)`
        // evaluated at the pre-call state.
        shares = previewDeposit(assets);
        IERC20(underlying).transferFrom(msg.sender, address(this), assets);

        if (mode == Mode.SharePriceDrop && totalSupply() != 0) {
            // Dilute incumbents: mint extra shares without backing assets, only after the vault is
            // already seeded so the initial deposit can establish a non-zero share price.
            shares = shares * 2;
        }

        if (mode == Mode.InflatedDepositShares) {
            shares += 100;
        }

        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = previewMint(shares);
        IERC20(underlying).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (mode == Mode.DepressedWithdrawShares) {
            if (shares > 100) shares -= 100;
        }

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        IERC20(underlying).transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        assets = previewRedeem(shares);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        IERC20(underlying).transfer(receiver, assets);
    }
}
