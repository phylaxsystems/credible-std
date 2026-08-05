# euler examples

Assertion examples and supporting helpers extracted from the `eulerv2` branch.

The full `EulerEVaultAssertion` and standalone per-call share-price wrapper are unavailable and
register no triggers. Supported EVK hooks and causal debt-socialization attribution must be modeled
before activation. The user-storage accounting wrapper remains independently available.

## Build

```sh
FOUNDRY_PROFILE=euler forge build
```

## Files

- EulerEVaultAssertion.sol
- EulerEVaultCircuitBreakerAssertion.sol
- EulerEVaultHelpers.sol
- EulerEVaultInterfaces.sol
- EulerEVaultSandwichAssertion.sol
- EulerEVaultSandwichHelpers.sol
