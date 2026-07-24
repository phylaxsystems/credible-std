// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {SymbioticVaultBaseAssertion} from "./SymbioticVaultBaseAssertion.sol";
import {SymbioticVaultCircuitBreakerAssertion} from "./SymbioticVaultCircuitBreakerAssertion.sol";
import {SymbioticVaultConfigAssertion} from "./SymbioticVaultConfigAssertion.sol";
import {SymbioticVaultFlowAssertion} from "./SymbioticVaultFlowAssertion.sol";

/// @title SymbioticVaultAssertion
/// @author Phylax Systems
/// @notice Concrete accounting assertion bundle for legacy Symbiotic v1 vaults.
/// @dev The contract keeps the old constructor shape for deployment compatibility, but only the
///      call-scoped v1 accounting checks are armed. Configuration ranges and rolling net-flow
///      breakers are operator policies rather than Symbiotic invariants.
///      This matches the `origin/spark` pattern where small reusable assertion contracts inherit
///      a shared base, and the top-level assertion only wires constructors and triggers.
///
///      - flow assertions protect against mis-accounted deposits, premature withdrawals,
///        underpaid claims, and broken stake bucket accounting;
///      - config assertions protect against half-initialized or economically unsafe vault setup;
///      - circuit breakers protect against abnormal collateral flight while still allowing
///        liquidation and healing paths.
contract SymbioticVaultAssertion is
    SymbioticVaultFlowAssertion,
    SymbioticVaultConfigAssertion,
    SymbioticVaultCircuitBreakerAssertion
{
    constructor(
        address vault_,
        address asset_,
        VaultConfigPolicy memory policy_,
        LiquidationRoute[] memory liquidationRoutes_
    )
        SymbioticVaultBaseAssertion(vault_, asset_)
        SymbioticVaultConfigAssertion(policy_)
        SymbioticVaultCircuitBreakerAssertion(liquidationRoutes_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires the v1 call-scoped accounting checks.
    function triggers() external view override {
        _registerVaultFlowTriggers();
    }
}
