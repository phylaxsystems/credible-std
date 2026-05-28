// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SymbioticHelpers} from "./SymbioticHelpers.sol";

/// @title SymbioticVaultBaseAssertion
/// @author Phylax Systems
/// @notice Shared base contract for Symbiotic vault assertions.
/// @dev Mirrors the `origin/spark` pattern: small abstract invariant modules inherit this base,
///      then a concrete bundle contract composes them and implements `triggers()`.
abstract contract SymbioticVaultBaseAssertion is SymbioticHelpers {
    /// @notice The Symbiotic vault being monitored.
    address internal immutable vault;

    /// @notice The ERC-20 collateral backing the vault.
    address internal immutable asset;

    /// @dev `asset_` is passed explicitly so the constructor never reads `vault_.collateral()`.
    ///      The Credible Layer's assertion-deploy runtime is isolated from the adopter; live
    ///      protocol reads during construction would revert with EXTCODESIZE = 0.
    constructor(address vault_, address asset_) {
        require(vault_ != address(0), "SymbioticVaultBase: vault is zero");
        vault = vault_;
        asset = asset_;
    }
}
