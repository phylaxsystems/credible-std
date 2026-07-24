// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "../../../SpecRecorder.sol";

import {ERC4626BaseAssertion} from "../ERC4626BaseAssertion.sol";
import {ERC4626PreviewAssertion} from "../ERC4626PreviewAssertion.sol";

/// @title MetaMorphoVaultAssertion
/// @author Phylax Systems
/// @notice Example ERC-4626 assertion bundle for MetaMorpho vaults.
/// @dev MetaMorpho reports managed assets held in Morpho markets. User operations temporarily move
///      assets and shares at different internal call boundaries, and ordinary withdrawals have
///      equal vault inflow and outflow legs. This bundle therefore keeps only the ERC-4626 preview
///      directions that MetaMorpho's implementation supports. Managed-asset loss and flow policy
///      need a MetaMorpho-specific adapter rather than the generic share-price or idle-balance
///      circuit-breaker primitives.
contract MetaMorphoVaultAssertion is ERC4626PreviewAssertion {
    /// @param vault_ MetaMorpho vault instance whose selectors this bundle will monitor.
    /// @param asset_ Underlying ERC-20 asset of the vault.
    constructor(address vault_, address asset_) ERC4626BaseAssertion(vault_, asset_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the ERC-4626 selectors against the MetaMorpho-safe assertion set.
    /// @dev MetaMorpho-specific managed-asset and loss accounting must be installed separately.
    function triggers() external view override {
        _registerPreviewTriggers();
    }
}
