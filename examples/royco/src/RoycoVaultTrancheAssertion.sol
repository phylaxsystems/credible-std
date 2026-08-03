// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {RoycoTrancheType, RoycoVaultTrancheHelpers} from "./RoycoHelpers.sol";
import {RoycoVaultTrancheOperationAssertion} from "./RoycoVaultTrancheOperationAssertion.sol";

/// @title RoycoVaultTrancheAssertion
/// @author Phylax Systems
/// @notice This bundle checks the tranche-facing share mechanics and call
///         ordering that LPs rely on. It keeps deposit/redeem previews aligned with actual
///         execution, verifies receiver/owner share effects, and ensures redeem paths call
///         into the kernel before shares are burned.
/// @dev Adopt this on each Royco tranche you want to monitor.
contract RoycoVaultTrancheAssertion is RoycoVaultTrancheOperationAssertion {
    constructor(address tranche_, address kernel_, RoycoTrancheType trancheType_)
        RoycoVaultTrancheHelpers(tranche_, kernel_, trancheType_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        // Quarantined: preview, return, and share deltas do not prove the official asset transfer
        // into the Kernel on deposit or to the receiver on redeem.
    }
}
