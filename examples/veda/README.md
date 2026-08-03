# veda examples

Assertion examples and supporting helpers extracted from the `ink/assertions` branch.

Every zero-asset-amount exit is treated as a share-only burn, regardless of the supplied asset
address, and requires an explicitly authorized caller.

## Build

```sh
FOUNDRY_PROFILE=veda forge build
```

## Files

- BoringVaultAssertion.sol
- BoringVaultHelpers.sol
- BoringVaultInterfaces.sol
