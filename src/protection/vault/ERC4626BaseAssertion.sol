// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {IERC4626} from "./IERC4626.sol";

/// @title ERC4626BaseAssertion
/// @author Phylax Systems
/// @notice Base contract for ERC-4626 vault assertions (V2 syntax).
/// @dev Provides vault-specific state accessors on top of the shared Assertion helpers.
///      Inherit from this (and one or more invariant contracts), then implement `triggers()`.
///
/// Example – combine share-price and preview invariants:
/// ```solidity
/// contract MyVaultAssertion is ERC4626SharePriceAssertion, ERC4626PreviewAssertion {
///     constructor(address _vault)
///         ERC4626BaseAssertion(_vault)
///         ERC4626SharePriceAssertion(50) // 50 bps tolerance
///     {}
///
///     function triggers() external view override {
///         _registerSharePriceTriggers();
///         _registerPreviewTriggers();
///     }
/// }
/// ```
abstract contract ERC4626BaseAssertion is Assertion {
    /// @notice The ERC-4626 vault being monitored (assertion adopter).
    address internal immutable vault;

    /// @notice The underlying ERC-20 asset of the vault.
    address internal immutable asset;

    constructor(address _vault) {
        vault = _vault;
        asset = IERC4626(_vault).asset();
    }

    // ---------------------------------------------------------------
    //  ERC-4626 state accessors
    // ---------------------------------------------------------------

    function _totalAssetsAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IERC4626.totalAssets, ()), fork);
    }

    function _totalSupplyAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IERC4626.totalSupply, ()), fork);
    }

    function _shareBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IERC4626.balanceOf, (account)), fork);
    }

    /// @dev Uses the same `balanceOf(address)` selector — valid for any ERC-20.
    function _assetBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(asset, abi.encodeCall(IERC4626.balanceOf, (account)), fork);
    }
}
