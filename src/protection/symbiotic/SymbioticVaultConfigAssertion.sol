// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {SymbioticHelpers} from "./SymbioticHelpers.sol";

/// @title SymbioticVaultConfigAssertion
/// @author Phylax Systems
/// @notice Configuration assertions for newly deployed Symbiotic vaults.
/// @dev This layer complements the deposit/withdraw flow assertions by checking that a vault is
///      wired up sanely for delegation and slashing. Some checks are hard protocol sanity, while
///      others are optional policy opinions derived from the docs and can be turned on or off.
abstract contract SymbioticVaultConfigAssertion is SymbioticHelpers {
    /// @notice Policy knobs for the config assertion.
    /// @dev Keep the hard protocol facts enabled, and only opt into the stronger recommendations
    ///      when they match the deployment's intended risk model.
    struct VaultConfigPolicy {
        bool requireCompleteInitialization;
        bool requireSlasher;
        bool requireDelegatorVaultMatch;
        bool requireSlasherVaultMatch;
        bool requireBurnerWhenSlasherHooked;
        uint48 minEpochDuration;
        uint48 maxEpochDuration;
        uint48 minVetoExecutionWindow;
        uint256 minResolverSetEpochsDelay;
    }

    address internal immutable vault;
    VaultConfigPolicy internal policy;

    constructor(address vault_, VaultConfigPolicy memory policy_) {
        vault = vault_;
        policy = policy_;
    }

    /// @notice Register the standard tx-end trigger for vault configuration checks.
    function _registerVaultConfigTriggers() internal view {
        registerTxEndTrigger(this.assertVaultConfiguration.selector);
    }

    /// @notice Checks that the vault is fully wired and respects the selected config policy.
    function assertVaultConfiguration() external view {
        PhEvm.ForkId memory postTx = _postTx();
        bool isInitialized = _isInitializedAt(vault, postTx);
        bool isDelegatorInitialized = _isDelegatorInitializedAt(vault, postTx);
        bool isSlasherInitialized = _isSlasherInitializedAt(vault, postTx);
        address delegator = _delegatorAddressAt(vault, postTx);
        address slasher = _slasherAddressAt(vault, postTx);
        address burner = _burnerAt(vault, postTx);
        uint256 epochDuration = _epochDurationAt(vault, postTx);

        // Symbiotic documents `isInitialized()` as "delegator set and slasher set".
        require(
            isInitialized == (isDelegatorInitialized && isSlasherInitialized),
            "SymbioticConfig: vault init flags are inconsistent"
        );

        // New vaults should not stay half-configured after deployment/setup transactions complete.
        if (policy.requireCompleteInitialization) {
            require(isInitialized, "SymbioticConfig: vault is not fully initialized");
            require(delegator != address(0), "SymbioticConfig: delegator missing after initialization");
        }

        if (policy.requireDelegatorVaultMatch && delegator != address(0)) {
            require(
                _delegatorVaultAt(delegator, postTx) == vault, "SymbioticConfig: delegator points at a different vault"
            );
        }

        // "No slashing" is valid in Symbiotic, but if the deployment expects a slashable vault,
        // treat a zero slasher as a hard failure.
        if (policy.requireSlasher) {
            require(slasher != address(0), "SymbioticConfig: slashable vault expected but slasher is zero");
            require(isSlasherInitialized, "SymbioticConfig: slasher expected but not initialized");
        }

        // Epoch duration drives both withdrawal delay and the slashing guarantee window.
        if (policy.minEpochDuration != 0) {
            require(epochDuration >= policy.minEpochDuration, "SymbioticConfig: epoch duration is too short");
        }
        if (policy.maxEpochDuration != 0) {
            require(epochDuration <= policy.maxEpochDuration, "SymbioticConfig: epoch duration is too long");
        }

        if (slasher == address(0)) {
            return;
        }

        if (policy.requireSlasherVaultMatch) {
            require(_slasherVaultAt(slasher, postTx) == vault, "SymbioticConfig: slasher points at a different vault");
        }

        // Slashers use `block.timestamp - epochDuration` style windows, so absurdly long epochs
        // eventually make slashing math unusable. The docs call out "greater than current timestamp"
        // as the technical edge case.
        require(epochDuration <= block.timestamp, "SymbioticConfig: epoch duration exceeds timestamp-safe bound");

        // A burner-hook slasher with a zero burner is explicitly unsupported by Symbiotic.
        if (policy.requireBurnerWhenSlasherHooked && _slasherIsBurnerHookAt(slasher, postTx)) {
            require(burner != address(0), "SymbioticConfig: burner hook enabled but burner is zero");
        }

        (bool isVetoSlasher, uint256 vetoDuration) = _tryVetoDurationAt(slasher, postTx);
        if (!isVetoSlasher) {
            return;
        }

        // Veto slashers must leave some part of the epoch after the veto window for execution.
        require(vetoDuration < epochDuration, "SymbioticConfig: veto duration must be less than epoch duration");

        if (policy.minVetoExecutionWindow != 0) {
            require(
                epochDuration - vetoDuration >= policy.minVetoExecutionWindow,
                "SymbioticConfig: veto window leaves too little execution buffer"
            );
        }

        if (policy.minResolverSetEpochsDelay != 0) {
            (bool hasResolverDelay, uint256 resolverSetEpochsDelay) = _tryResolverSetEpochsDelayAt(slasher, postTx);
            require(hasResolverDelay, "SymbioticConfig: veto slasher missing resolver delay getter");
            require(
                resolverSetEpochsDelay >= policy.minResolverSetEpochsDelay,
                "SymbioticConfig: resolver delay is too short"
            );
        }
    }
}

/// @title SymbioticVaultConfigProtection
/// @notice Ready-to-use bundle for Symbiotic vault configuration assertions with custom policy.
contract SymbioticVaultConfigProtection is SymbioticVaultConfigAssertion {
    constructor(address vault_, VaultConfigPolicy memory policy_) SymbioticVaultConfigAssertion(vault_, policy_) {}

    function triggers() external view override {
        _registerVaultConfigTriggers();
    }
}

/// @title SymbioticVaultRecommendedConfigProtection
/// @notice Convenience bundle using docs-inspired defaults without forcing a slashable vault.
contract SymbioticVaultRecommendedConfigProtection is SymbioticVaultConfigAssertion {
    constructor(address vault_)
        SymbioticVaultConfigAssertion(
            vault_,
            VaultConfigPolicy({
                requireCompleteInitialization: true,
                requireSlasher: false,
                requireDelegatorVaultMatch: true,
                requireSlasherVaultMatch: true,
                requireBurnerWhenSlasherHooked: true,
                minEpochDuration: 1 days,
                maxEpochDuration: 30 days,
                minVetoExecutionWindow: 0,
                minResolverSetEpochsDelay: 3
            })
        )
    {}

    function triggers() external view override {
        _registerVaultConfigTriggers();
    }
}
