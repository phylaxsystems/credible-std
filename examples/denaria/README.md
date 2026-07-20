# Denaria examples

The included Solidity adapter targets Denaria's legacy `PerpPair` and `Vault` ABI. It is retained as
reference code, but its assertion triggers are intentionally disabled: current production writes use
the Stylus `PerpEngine` `*For` selectors and different insurance/event/accounting semantics.

Do not activate `DenariaProtectionSuite` against a current deployment. A production adapter must be
rebuilt from the deployed Stylus ABI and must bind the explicit user carried by each `*For` call.

## Build

```sh
FOUNDRY_PROFILE=denaria forge build
```

## Reference files

- DenariaHelpers.sol
- DenariaInterfaces.sol
- DenariaOperationSafety.sol
