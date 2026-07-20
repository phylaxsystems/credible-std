# symbiotic examples

Assertion examples and supporting helpers extracted from the `symbiotic` branch.

## Build

```sh
FOUNDRY_PROFILE=symbiotic forge build
```

## Files

The ready-to-use vault bundle now arms only call-scoped v1 accounting checks, including claimant
entitlement, active-share ownership, and slashing bucket conservation. The generic rolling-flow
breaker, recommended configuration bundle, and relay bundle register no triggers because their
original observations could reject valid protocol configurations or accept unrelated escape calls.
The custom configuration contract remains an explicit operator policy and must be calibrated for
the deployment. None of these contracts should be attached to VaultV2 without a version-specific
adapter.

- SymbioticHelpers.sol
- SymbioticInterfaces.sol
- SymbioticRelayAssertion.sol
- SymbioticVaultAssertion.sol
- SymbioticVaultBaseAssertion.sol
- SymbioticVaultCircuitBreakerAssertion.sol
- SymbioticVaultConfigAssertion.sol
- SymbioticVaultFlowAssertion.sol
- SymbioticVaultFlowHelpers.sol
