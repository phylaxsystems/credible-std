// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {IFluidVaultResolverLike} from "./FluidInterfaces.sol";

/// @title FluidVaultRiskConfigAssertion
/// @author Phylax Systems
/// @notice Keeps a Fluid Vault's risk parameters in a liquidatable ordering after any transaction.
/// @dev Install on a Fluid Vault (the assertion adopter). The vault's admin module enforces
///      `collateralFactor < liquidationThreshold < liquidationMaxLimit` and
///      `liquidationMaxLimit + liquidationPenalty <= 99.7%` only inside its setters. This assertion
///      re-checks the same ordering on the *stored* config after the transaction, regardless of how
///      it was written (setter, faulty upgrade, storage-collision, delegatecall exploit). That makes
///      it safe for governance to tune aggressive parameters for riskier collateral: the protocol
///      can push CF/LT high, and this assertion guarantees the invariant that keeps every position
///      liquidatable still holds in the actual stored state.
///
///      Config is read from the maintained `FluidVaultResolver.getVaultVariables2Raw(vault)` getter
///      and decoded from the `vaultVariables2` word. Field bit offsets and scales are from Fluid's
///      vault admin module: collateralFactor/liquidationThreshold/liquidationMaxLimit are stored as
///      `input / 10` (so 100% = 1000), liquidationPenalty is stored as-is in 1e2 (so 100% = 10000).
contract FluidVaultRiskConfigAssertion is Assertion {
    uint256 internal constant CONFIG_MASK = 0x3FF; // X10: 10-bit fields

    uint256 internal constant BITS_COLLATERAL_FACTOR = 32;
    uint256 internal constant BITS_LIQUIDATION_THRESHOLD = 42;
    uint256 internal constant BITS_LIQUIDATION_MAX_LIMIT = 52;
    uint256 internal constant BITS_LIQUIDATION_PENALTY = 72;

    /// @notice 100% for the CF/LT/LML fields in their stored (`input / 10`) scale.
    uint256 internal constant STORED_HUNDRED_PERCENT = 1_000;

    /// @notice Protocol cap on `liquidationMaxLimit + liquidationPenalty`, in 1e2 scale (99.7%).
    uint256 internal constant MAX_LML_PLUS_PENALTY_1E2 = 9_970;

    /// @notice FluidVaultResolver used to read the vault's packed config word.
    address internal immutable VAULT_RESOLVER;

    /// @param vaultResolver_ Address of the deployed FluidVaultResolver.
    constructor(address vaultResolver_) {
        VAULT_RESOLVER = vaultResolver_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Re-checks the vault risk-config ordering at transaction end.
    function triggers() external view override {
        registerTxEndTrigger(this.assertRiskConfigOrdering.selector);
    }

    /// @notice The vault's stored risk parameters keep positions liquidatable.
    /// @dev Property after the transaction:
    ///      - `collateralFactor < liquidationThreshold` (borrowers cannot open at the liquidation line),
    ///      - `liquidationThreshold < liquidationMaxLimit` (a band exists for partial liquidation),
    ///      - `liquidationMaxLimit <= 100%`,
    ///      - `liquidationMaxLimit + liquidationPenalty <= 99.7%` (liquidators keep an incentive and
    ///        seized collateral cannot exceed available value).
    ///      A failure means the stored config was left in a state where positions could become
    ///      unliquidatable or liquidations could over-seize — even if no setter `require` was hit.
    function assertRiskConfigOrdering() external view {
        uint256 vaultVariables2 = _readUintAt(
            VAULT_RESOLVER,
            abi.encodeCall(IFluidVaultResolverLike.getVaultVariables2Raw, (ph.getAssertionAdopter())),
            _postTx()
        );

        uint256 collateralFactor = (vaultVariables2 >> BITS_COLLATERAL_FACTOR) & CONFIG_MASK;
        uint256 liquidationThreshold = (vaultVariables2 >> BITS_LIQUIDATION_THRESHOLD) & CONFIG_MASK;
        uint256 liquidationMaxLimit = (vaultVariables2 >> BITS_LIQUIDATION_MAX_LIMIT) & CONFIG_MASK;
        uint256 liquidationPenalty = (vaultVariables2 >> BITS_LIQUIDATION_PENALTY) & CONFIG_MASK;

        require(collateralFactor < liquidationThreshold, "Fluid: collateral factor >= liquidation threshold");
        require(liquidationThreshold < liquidationMaxLimit, "Fluid: liquidation threshold >= max limit");
        require(liquidationMaxLimit <= STORED_HUNDRED_PERCENT, "Fluid: liquidation max limit above 100%");

        // CF/LT/LML are stored as input/10; scale LML back to 1e2 to compare against the penalty.
        require(
            liquidationMaxLimit * 10 + liquidationPenalty <= MAX_LML_PLUS_PENALTY_1E2,
            "Fluid: liquidation max limit + penalty above 99.7%"
        );
    }
}
