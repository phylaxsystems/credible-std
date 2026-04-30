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
/// Example – combine share-price, preview, and outflow invariants:
/// ```solidity
/// contract MyVaultAssertion is ERC4626SharePriceAssertion, ERC4626PreviewAssertion, ERC4626CumulativeOutflowAssertion {
///     constructor(address _vault, address _asset)
///         ERC4626BaseAssertion(_vault, _asset)
///         ERC4626SharePriceAssertion(50) // 50 bps tolerance
///         ERC4626CumulativeOutflowAssertion(1_000, 24 hours) // 10% in 24h
///     {}
///
///     function triggers() external view override {
///         _registerSharePriceTriggers();
///         _registerPreviewTriggers();
///         _registerCumulativeOutflowTriggers();
///     }
/// }
/// ```
abstract contract ERC4626BaseAssertion is Assertion {
    /// @notice The ERC-4626 vault being monitored (assertion adopter).
    address internal immutable vault;

    /// @notice The underlying ERC-20 asset of the vault.
    address internal immutable asset;

    /// @dev Accepts the asset address explicitly so the constructor never reads from the adopter.
    ///      The Credible Layer's assertion-deploy runtime is isolated from the calling test state,
    ///      so a `vault.asset()` call inside the constructor would revert with EXTCODESIZE = 0.
    /// @param _vault The ERC-4626 vault being monitored (assertion adopter).
    /// @param _asset The vault's underlying ERC-20 asset.
    constructor(address _vault, address _asset) {
        vault = _vault;
        asset = _asset;
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
        return _readBalanceAt(vault, account, fork);
    }

    /// @dev Uses the same `balanceOf(address)` selector — valid for any ERC-20.
    function _assetBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(asset, account, fork);
    }
}
