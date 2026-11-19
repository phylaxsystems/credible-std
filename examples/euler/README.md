# Euler examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Protocol-specific assertion examples and supporting helpers.

The full `EulerEVaultAssertion` and standalone per-call share-price wrapper are unavailable and
register no triggers. Supported EVK hooks and causal debt-socialization attribution must be modeled
before activation. The user-storage accounting wrapper remains independently available.

## Build and test

```sh
FOUNDRY_PROFILE=euler forge build
FOUNDRY_PROFILE=euler pcl test
```

## Files

- [EulerEVaultAssertion.sol](src/EulerEVaultAssertion.sol)
- [EulerEVaultCircuitBreakerAssertion.sol](src/EulerEVaultCircuitBreakerAssertion.sol)
- [EulerEVaultHelpers.sol](src/EulerEVaultHelpers.sol)
- [EulerEVaultInterfaces.sol](src/EulerEVaultInterfaces.sol)
- [EulerEVaultSandwichAssertion.sol](src/EulerEVaultSandwichAssertion.sol)
- [EulerEVaultSandwichHelpers.sol](src/EulerEVaultSandwichHelpers.sol)
