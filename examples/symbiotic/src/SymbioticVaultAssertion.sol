// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SymbioticVaultBaseAssertion} from "./SymbioticVaultBaseAssertion.sol";
import {SymbioticVaultCircuitBreakerAssertion} from "./SymbioticVaultCircuitBreakerAssertion.sol";
import {SymbioticVaultConfigAssertion} from "./SymbioticVaultConfigAssertion.sol";
import {SymbioticVaultFlowAssertion} from "./SymbioticVaultFlowAssertion.sol";

/// @title SymbioticVaultAssertion
/// @author Phylax Systems
/// @notice Spark-style concrete assertion bundle for Symbiotic vaults.
/// @dev Compose the abstract flow, config, and circuit-breaker modules behind one entrypoint.
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
    constructor(address vault_, VaultConfigPolicy memory policy_, LiquidationRoute[] memory liquidationRoutes_)
        SymbioticVaultBaseAssertion(vault_)
        SymbioticVaultConfigAssertion(policy_)
        SymbioticVaultCircuitBreakerAssertion(liquidationRoutes_)
    {}

    /// @notice Wires the full Symbiotic vault protection suite.
    /// @dev Per-call triggers watch user-facing vault mutations, tx-end checks catch config/state
    ///      drift that may emerge across a whole transaction, and cumulative-outflow watchers
    ///      provide rolling-window circuit breakers on the vault collateral.
    function triggers() external view override {
        _registerVaultFlowTriggers();
        _registerVaultConfigTriggers();
        _registerCircuitBreakerTriggers();
    }
}
