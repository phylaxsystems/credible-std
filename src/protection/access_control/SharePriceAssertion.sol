// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AccessControlBaseAssertion} from "./AccessControlBaseAssertion.sol";

/// @title SharePriceAssertion
/// @author Phylax Systems
/// @notice Asserts that ERC-4626 vault share prices do not deviate beyond a configurable
///         tolerance, protecting against admin-driven share price manipulation.
///
/// Invariants covered:
///   - **Share price stability**: the ratio totalAssets / totalSupply must not shift more
///     than `toleranceBps` across any fork point in the transaction.
///   - **Donation attack prevention**: catches inflated totalAssets without proportional
///     share minting.
///   - **First-depositor exploit prevention**: detects exchange rate manipulation with
///     tiny initial deposits followed by large donations.
///   - **Flash-loan manipulation**: flags temporary share price distortion within a
///     transaction.
///
/// @dev Uses the V2 `assetsMatchSharePrice` precompile for a comprehensive all-forks check.
///      This is a simpler mixin than the full ERC4626SharePriceAssertion -- it omits per-call
///      triggers and focuses on tx-wide share price envelope protection. Use this when the
///      access-control concern is preventing admin manipulation of share prices, rather than
///      enforcing full ERC-4626 compliance.
///
///      Implementers must override `_protectedVaults()` to declare which vault addresses and
///      tolerances to check.
abstract contract SharePriceAssertion is AccessControlBaseAssertion {
    /// @notice A vault and its maximum acceptable share-price deviation.
    struct ProtectedVault {
        /// @notice The ERC-4626 vault address.
        address vault;
        /// @notice Maximum allowed share price deviation in basis points. 100 = 1%.
        uint256 toleranceBps;
    }

    /// @notice Returns the vaults whose share prices must remain stable across the transaction.
    /// @dev Override to declare the protocol-specific vault addresses and tolerances.
    ///      Tighter tolerances (e.g., 10 bps) are appropriate for stablecoin vaults;
    ///      wider tolerances (e.g., 50-100 bps) may be needed for volatile-asset vaults
    ///      or vaults with rebasing underlying assets.
    /// @return vaults Array of (vault, toleranceBps) pairs to protect.
    function _protectedVaults() internal view virtual returns (ProtectedVault[] memory vaults);

    /// @notice Register the default trigger set for share price protection.
    /// @dev Uses registerTxEndTrigger so the check fires once after the transaction completes.
    ///      Call this inside your `triggers()`.
    function _registerSharePriceTriggers() internal view {
        registerTxEndTrigger(this.assertSharePrice.selector);
    }

    /// @notice Verifies that all protected vault share prices are stable across the transaction.
    /// @dev Uses `ph.assetsMatchSharePrice()` for each vault, which reads totalAssets() and
    ///      totalSupply() at every fork point and checks for deviation beyond the tolerance.
    ///      Reverts on the first vault whose share price moved beyond tolerance.
    function assertSharePrice() external {
        ProtectedVault[] memory vaults = _protectedVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            require(
                ph.assetsMatchSharePrice(vaults[i].vault, vaults[i].toleranceBps),
                "AccessControl: vault share price drift exceeds tolerance"
            );
        }
    }
}
