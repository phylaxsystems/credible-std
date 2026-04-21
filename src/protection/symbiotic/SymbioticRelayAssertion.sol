// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SymbioticHelpers} from "./SymbioticHelpers.sol";
import {
    ISymbioticVaultLike,
    ISymbioticDelegatorLike,
    ISymbioticVotingPowerProviderLike
} from "./SymbioticInterfaces.sol";

/// @title SymbioticRelayAssertion
/// @author Phylax Systems
/// @notice Relay-side assertions for operator vault registration, collateral coherence,
///         equal-stake voting power, and the optional auto-deploy network-limit hook.
/// @dev Register this against the relay VotingPowerProvider / OpNetVaultAutoDeploy contract.
contract SymbioticRelayAssertion is SymbioticHelpers {
    address internal immutable provider;
    bytes32 internal immutable subnetwork;
    bytes internal operatorVotingPowerExtraData;

    constructor(address provider_, bytes32 subnetwork_, bytes memory operatorVotingPowerExtraData_) {
        provider = provider_;
        subnetwork = subnetwork_;
        operatorVotingPowerExtraData = operatorVotingPowerExtraData_;
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertRegisteredOperatorVaultsUseRegisteredCollateral.selector);
        registerTxEndTrigger(this.assertAutoDeployedVaultRegistrationCoherence.selector);
        registerTxEndTrigger(this.assertEqualStakeVotingPower.selector);
        registerTxEndTrigger(this.assertAutoDeployMaxNetworkLimitHook.selector);
    }

    /// @notice Every registered operator vault should still use a relay-registered collateral token.
    function assertRegisteredOperatorVaultsUseRegisteredCollateral() external view {
        address[] memory operators = _asProvider(provider).getOperators();
        for (uint256 i; i < operators.length; ++i) {
            address[] memory vaults = _asProvider(provider).getOperatorVaults(operators[i]);
            for (uint256 j; j < vaults.length; ++j) {
                // The relay's operator->vault list should agree with its registration check.
                require(
                    _asProvider(provider).isOperatorVaultRegistered(operators[i], vaults[j]),
                    "SymbioticRelay: listed operator vault is not registered"
                );
                // Relay voting power assumptions only make sense if the vault collateral is still accepted.
                require(
                    _asProvider(provider).isTokenRegistered(ISymbioticVaultLike(vaults[j]).collateral()),
                    "SymbioticRelay: operator vault collateral is not registered"
                );
            }
        }
    }

    /// @notice Auto-deployed vault pointers must agree with the operator vault registry.
    function assertAutoDeployedVaultRegistrationCoherence() external view {
        address[] memory operators = _asProvider(provider).getOperators();
        for (uint256 i; i < operators.length; ++i) {
            address autoVault = _asAutoDeploy(provider).getAutoDeployedVault(operators[i]);
            if (autoVault == address(0)) {
                continue;
            }

            // Auto-deploy should not leave behind a stale pointer to an unregistered vault.
            require(
                _asProvider(provider).isOperatorVaultRegistered(operators[i], autoVault),
                "SymbioticRelay: auto-deployed vault is not registered for operator"
            );
            require(
                _containsAddress(_asProvider(provider).getOperatorVaults(operators[i]), autoVault),
                "SymbioticRelay: auto-deployed vault missing from operator vault set"
            );
        }
    }

    /// @notice Under EqualStakeVPCalc, voting power should match stake for registered-collateral vaults.
    function assertEqualStakeVotingPower() external view {
        address[] memory operators = _asProvider(provider).getOperators();
        for (uint256 i; i < operators.length; ++i) {
            ISymbioticVotingPowerProviderLike.VaultValue[] memory stakes =
                _asProvider(provider).getOperatorStakes(operators[i]);
            ISymbioticVotingPowerProviderLike.VaultValue[] memory votingPowers =
                _asProvider(provider).getOperatorVotingPowers(operators[i], operatorVotingPowerExtraData);

            for (uint256 j; j < stakes.length; ++j) {
                address collateral = ISymbioticVaultLike(stakes[j].vault).collateral();
                if (!_asProvider(provider).isTokenRegistered(collateral)) {
                    continue;
                }

                // With EqualStakeVPCalc, "stake" and "voting power" should be the same number.
                (bool found, uint256 votingPower) = _findVaultValue(votingPowers, stakes[j].vault);
                require(found, "SymbioticRelay: missing voting power entry for registered stake");
                require(votingPower == stakes[j].value, "SymbioticRelay: equal-stake voting power mismatch");
            }
        }
    }

    /// @notice When the max-network-limit hook is enabled, auto-deployed vaults should expose full subnetwork availability.
    function assertAutoDeployMaxNetworkLimitHook() external view {
        if (!_asAutoDeploy(provider).isSetMaxNetworkLimitHookEnabled()) {
            return;
        }

        address[] memory operators = _asProvider(provider).getOperators();
        for (uint256 i; i < operators.length; ++i) {
            address autoVault = _asAutoDeploy(provider).getAutoDeployedVault(operators[i]);
            if (autoVault == address(0) || !_asProvider(provider).isOperatorVaultRegistered(operators[i], autoVault)) {
                continue;
            }

            address delegator = ISymbioticVaultLike(autoVault).delegator();
            // When this hook is on, newly auto-deployed vaults should be fully available to the relay subnetwork.
            require(
                ISymbioticDelegatorLike(delegator).maxNetworkLimit(subnetwork) == type(uint256).max,
                "SymbioticRelay: max network limit hook did not set full availability"
            );
        }
    }
}
