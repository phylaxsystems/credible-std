# Denaria examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

The included Solidity adapter targets Denaria's legacy `PerpPair` and `Vault` ABI. It is retained as
reference code, but its assertion triggers are intentionally disabled: current production writes use
the Stylus `PerpEngine` `*For` selectors and different insurance/event/accounting semantics.

Do not activate `DenariaProtectionSuite` against a current deployment. A production adapter must be
rebuilt from the deployed Stylus ABI and must bind the explicit user carried by each `*For` call.

## Build and test

```sh
FOUNDRY_PROFILE=denaria forge build
FOUNDRY_PROFILE=denaria pcl test
```

## Reference files

- [DenariaHelpers.sol](src/DenariaHelpers.sol)
- [DenariaInterfaces.sol](src/DenariaInterfaces.sol)
- [DenariaOperationSafety.sol](src/DenariaOperationSafety.sol)
