// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {SymbioticVaultBaseAssertion} from "./SymbioticVaultBaseAssertion.sol";

/// @title SymbioticVaultConfigAssertion
/// @author Phylax Systems
/// @notice Configuration assertions for newly deployed Symbiotic vaults.
/// @dev This layer complements the deposit/withdraw flow assertions by checking that a vault is
///      wired up sanely for delegation and slashing. Some checks are hard protocol sanity, while
///      others are optional policy opinions derived from the docs and can be turned on or off.
///
///      - protects against deploying a vault that is still only partially initialized;
///      - protects against accidentally launching with missing or miswired delegator/slasher links;
///      - protects against unsafe timing parameters such as absurd epochs or veto windows;
///      - protects against burner-hook slashers that cannot actually route slashed funds.
abstract contract SymbioticVaultConfigAssertion is SymbioticVaultBaseAssertion {
    struct VaultConfigState {
        bool isInitialized;
        bool isDelegatorInitialized;
        bool isSlasherInitialized;
        address delegator;
        address slasher;
        address burner;
        uint256 epochDuration;
    }

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

    VaultConfigPolicy internal policy;

    constructor(VaultConfigPolicy memory policy_) {
        policy = policy_;
    }

    /// @notice Register the standard tx-end trigger for vault configuration checks.
    /// @dev Config safety is a whole-state property, so we check it once after the transaction
    ///      rather than tying it to a single mutator selector.
    function _registerVaultConfigTriggers() internal view {
        registerTxEndTrigger(this.assertVaultConfiguration.selector);
    }

    /// @notice Checks that the vault is fully wired and respects the selected config policy.
    /// @dev Protects against deployment/setup footguns that leave the vault only partially usable
    ///      or economically weaker than intended. After the transaction, the vault wiring and
    ///      timing parameters should satisfy both Symbiotic's hard constraints and the chosen policy.
    function assertVaultConfiguration() external view {
        PhEvm.ForkId memory postTx = _postTx();
        VaultConfigState memory state = _vaultConfigStateAt(postTx);

        _assertInitializationConsistency(state);
        _assertRequiredInitialization(state);
        _assertVaultLinkage(state, postTx);
        _assertEpochDurationBounds(state);

        if (state.slasher == address(0)) {
            return;
        }

        _assertSlasherConfiguration(state, postTx);
        _assertBurnerConfiguration(state, postTx);
        _assertVetoConfiguration(state, postTx);
    }

    function _vaultConfigStateAt(PhEvm.ForkId memory fork) internal view returns (VaultConfigState memory state) {
        state = VaultConfigState({
            isInitialized: _isInitializedAt(vault, fork),
            isDelegatorInitialized: _isDelegatorInitializedAt(vault, fork),
            isSlasherInitialized: _isSlasherInitializedAt(vault, fork),
            delegator: _delegatorAddressAt(vault, fork),
            slasher: _slasherAddressAt(vault, fork),
            burner: _burnerAt(vault, fork),
            epochDuration: _epochDurationAt(vault, fork)
        });
    }

    function _assertInitializationConsistency(VaultConfigState memory state) internal pure {
        require(
            state.isInitialized == (state.isDelegatorInitialized && state.isSlasherInitialized),
            "SymbioticConfig: vault init flags are inconsistent"
        );
    }

    function _assertRequiredInitialization(VaultConfigState memory state) internal view {
        if (!policy.requireCompleteInitialization) {
            return;
        }

        require(state.isInitialized, "SymbioticConfig: vault is not fully initialized");
        require(state.delegator != address(0), "SymbioticConfig: delegator missing after initialization");

        if (policy.requireSlasher) {
            require(state.slasher != address(0), "SymbioticConfig: slashable vault expected but slasher is zero");
            require(state.isSlasherInitialized, "SymbioticConfig: slasher expected but not initialized");
        }
    }

    function _assertVaultLinkage(VaultConfigState memory state, PhEvm.ForkId memory postTx) internal view {
        if (policy.requireDelegatorVaultMatch && state.delegator != address(0)) {
            require(
                _delegatorVaultAt(state.delegator, postTx) == vault,
                "SymbioticConfig: delegator points at a different vault"
            );
        }

        if (policy.requireSlasher && !policy.requireCompleteInitialization) {
            require(state.slasher != address(0), "SymbioticConfig: slashable vault expected but slasher is zero");
            require(state.isSlasherInitialized, "SymbioticConfig: slasher expected but not initialized");
        }
    }

    function _assertEpochDurationBounds(VaultConfigState memory state) internal view {
        if (policy.minEpochDuration != 0) {
            require(state.epochDuration >= policy.minEpochDuration, "SymbioticConfig: epoch duration is too short");
        }
        if (policy.maxEpochDuration != 0) {
            require(state.epochDuration <= policy.maxEpochDuration, "SymbioticConfig: epoch duration is too long");
        }
    }

    function _assertSlasherConfiguration(VaultConfigState memory state, PhEvm.ForkId memory postTx) internal view {
        if (policy.requireSlasherVaultMatch) {
            require(
                _slasherVaultAt(state.slasher, postTx) == vault, "SymbioticConfig: slasher points at a different vault"
            );
        }

        require(
            state.epochDuration <= block.timestamp, "SymbioticConfig: epoch duration exceeds timestamp-safe bound"
        );
    }

    function _assertBurnerConfiguration(VaultConfigState memory state, PhEvm.ForkId memory postTx) internal view {
        if (policy.requireBurnerWhenSlasherHooked && _slasherIsBurnerHookAt(state.slasher, postTx)) {
            require(state.burner != address(0), "SymbioticConfig: burner hook enabled but burner is zero");
        }
    }

    function _assertVetoConfiguration(VaultConfigState memory state, PhEvm.ForkId memory postTx) internal view {
        (bool isVetoSlasher, uint256 vetoDuration) = _tryVetoDurationAt(state.slasher, postTx);
        if (!isVetoSlasher) {
            return;
        }

        require(vetoDuration < state.epochDuration, "SymbioticConfig: veto duration must be less than epoch duration");

        if (policy.minVetoExecutionWindow != 0) {
            require(
                state.epochDuration - vetoDuration >= policy.minVetoExecutionWindow,
                "SymbioticConfig: veto window leaves too little execution buffer"
            );
        }

        if (policy.minResolverSetEpochsDelay != 0) {
            (bool hasResolverDelay, uint256 resolverSetEpochsDelay) =
                _tryResolverSetEpochsDelayAt(state.slasher, postTx);
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
/// @dev Use this when you want deployment/config sanity checks without the vault-flow or
///      circuit-breaker layers.
contract SymbioticVaultConfigProtection is SymbioticVaultConfigAssertion {
    constructor(address vault_, VaultConfigPolicy memory policy_)
        SymbioticVaultBaseAssertion(vault_)
        SymbioticVaultConfigAssertion(policy_)
    {}

    /// @notice Wires only the tx-end configuration trigger.
    /// @dev This bundle protects against half-configured or economically dangerous vault setup.
    function triggers() external view override {
        _registerVaultConfigTriggers();
    }
}

/// @title SymbioticVaultRecommendedConfigProtection
/// @notice Convenience bundle using docs-inspired defaults without forcing a slashable vault.
/// @dev This is the opinionated version of `SymbioticVaultConfigProtection`: it keeps the
///      documentation-backed safety defaults while still permitting an intentional no-slasher vault.
contract SymbioticVaultRecommendedConfigProtection is SymbioticVaultConfigAssertion {
    constructor(address vault_)
        SymbioticVaultBaseAssertion(vault_)
        SymbioticVaultConfigAssertion(VaultConfigPolicy({
                requireCompleteInitialization: true,
                requireSlasher: false,
                requireDelegatorVaultMatch: true,
                requireSlasherVaultMatch: true,
                requireBurnerWhenSlasherHooked: true,
                minEpochDuration: 1 days,
                maxEpochDuration: 30 days,
                minVetoExecutionWindow: 0,
                minResolverSetEpochsDelay: 3
            }))
    {}

    /// @notice Wires the recommended tx-end configuration policy.
    /// @dev This bundle is meant to catch the common Symbiotic deployment footguns from the docs.
    function triggers() external view override {
        _registerVaultConfigTriggers();
    }
}
