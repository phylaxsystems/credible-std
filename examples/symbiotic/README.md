# Symbiotic examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Protocol-specific assertion examples and supporting helpers.

## Build and test

```sh
FOUNDRY_PROFILE=symbiotic forge build
FOUNDRY_PROFILE=symbiotic pcl test
```

## Test coverage

The current suite checks construction or quarantine only. Retained `retired*`
functions are not executed tests, and a passing run does not demonstrate runtime
assertion protection.

## Files

The ready-to-use vault bundle and standalone flow wrapper are quarantined and register no triggers.
They must support valid self-recipient and fee-on-transfer behavior, scale batch claims within the
assertion gas budget, and bind an official v1 deployment before activation. The generic rolling-flow
breaker, recommended configuration bundle, and relay bundle register no triggers because their
original observations could reject valid protocol configurations or accept unrelated escape calls.
The custom configuration contract remains an explicit operator policy and must be calibrated for
the deployment. None of these contracts should be attached to VaultV2 without a version-specific
adapter.

- [SymbioticHelpers.sol](src/SymbioticHelpers.sol)
- [SymbioticInterfaces.sol](src/SymbioticInterfaces.sol)
- [SymbioticRelayAssertion.sol](src/SymbioticRelayAssertion.sol)
- [SymbioticVaultAssertion.sol](src/SymbioticVaultAssertion.sol)
- [SymbioticVaultBaseAssertion.sol](src/SymbioticVaultBaseAssertion.sol)
- [SymbioticVaultCircuitBreakerAssertion.sol](src/SymbioticVaultCircuitBreakerAssertion.sol)
- [SymbioticVaultConfigAssertion.sol](src/SymbioticVaultConfigAssertion.sol)
- [SymbioticVaultFlowAssertion.sol](src/SymbioticVaultFlowAssertion.sol)
- [SymbioticVaultFlowHelpers.sol](src/SymbioticVaultFlowHelpers.sol)
