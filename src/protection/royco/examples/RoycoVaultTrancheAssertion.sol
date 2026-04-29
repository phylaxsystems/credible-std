// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {RoycoVaultTrancheHelpers} from "../RoycoHelpers.sol";
import {RoycoVaultTrancheOperationAssertion} from "../RoycoVaultTrancheOperationAssertion.sol";

/// @title RoycoVaultTrancheAssertion
/// @author Phylax Systems
/// @notice Executive summary: this bundle checks the tranche-facing share mechanics and call
///         ordering that LPs rely on. It keeps deposit/redeem previews aligned with actual
///         execution, verifies protocol-fee and virtual-share math, and ensures redeem paths call
///         into the kernel before shares are burned.
/// @dev Adopt this on each Royco tranche you want to monitor.
contract RoycoVaultTrancheAssertion is RoycoVaultTrancheOperationAssertion {
    constructor(address tranche_) RoycoVaultTrancheHelpers(tranche_) {}

    function triggers() external view override {
        _registerOperationInvariantTriggers();
    }
}
