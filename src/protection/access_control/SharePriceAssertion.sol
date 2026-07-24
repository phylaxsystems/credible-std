// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AccessControlBaseAssertion} from "./AccessControlBaseAssertion.sol";

/// @title SharePriceAssertion
/// @author Phylax Systems
/// @notice Applies a symmetric endpoint share-price policy to configured ERC-4626 vaults.
///
/// Invariants covered:
///   - **Endpoint share price stability**: the ratio totalAssets / totalSupply must not shift more
///     than `toleranceBps` between transaction start and transaction end.
///   - **Donation policy**: catches endpoint increases without proportional share minting once the
///     vault already has nonzero supply.
///
/// @dev Uses the V2 `assetsMatchSharePriceAt` precompile at transaction endpoints only.
///      This is a simpler mixin than the full ERC4626SharePriceAssertion -- it omits per-call
///      triggers and focuses on tx-wide share price envelope protection. Use this when the
///      access-control concern is preventing admin manipulation of share prices, rather than
///      enforcing full ERC-4626 compliance.
///
///      This is a symmetric operator policy, not an ERC-4626 invariant: legitimate yield can move
///      the ratio upward. The executor skips comparisons when either endpoint supply is zero, so
///      first deposit, full burn, and zero-supply donation transitions are explicitly outside its
///      protection. Implementers must override `_protectedVaults()` to declare supported vaults
///      and must calibrate tolerances from those concrete implementations.
abstract contract SharePriceAssertion is AccessControlBaseAssertion {
    error SharePriceChanged(address vault, uint256 toleranceBps);

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

    /// @notice Verifies that all protected vault endpoint share prices are stable across the transaction.
    /// @dev Uses `ph.assetsMatchSharePriceAt()` for each vault at PreTx and PostTx. Intermediate
    ///      snapshots are excluded because healthy vaults often update assets and shares at
    ///      different moments inside one operation.
    ///      Reverts on the first vault whose share price moved beyond tolerance.
    function assertSharePrice() external view {
        ProtectedVault[] memory vaults = _protectedVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i].vault == address(0) || vaults[i].toleranceBps >= 10_000) {
                revert SharePriceChanged(vaults[i].vault, vaults[i].toleranceBps);
            }
            if (!ph.assetsMatchSharePriceAt(vaults[i].vault, vaults[i].toleranceBps, _preTx(), _postTx())) {
                revert SharePriceChanged(vaults[i].vault, vaults[i].toleranceBps);
            }
        }
    }
}
