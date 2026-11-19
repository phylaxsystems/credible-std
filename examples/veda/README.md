# Veda examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Protocol-specific assertion examples and supporting helpers.

Every zero-asset-amount exit is treated as a share-only burn, regardless of the supplied asset
address, and requires an explicitly authorized caller.

## Build and test

```sh
FOUNDRY_PROFILE=veda forge build
FOUNDRY_PROFILE=veda pcl test
```

## Files

- [BoringVaultAssertion.sol](src/BoringVaultAssertion.sol)
- [BoringVaultHelpers.sol](src/BoringVaultHelpers.sol)
- [BoringVaultInterfaces.sol](src/BoringVaultInterfaces.sol)
