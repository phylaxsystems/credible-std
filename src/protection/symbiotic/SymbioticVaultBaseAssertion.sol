// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ISymbioticVaultLike} from "./SymbioticInterfaces.sol";
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

    constructor(address vault_) {
        require(vault_ != address(0), "SymbioticVaultBase: vault is zero");
        vault = vault_;
        asset = ISymbioticVaultLike(vault_).collateral();
    }
}
