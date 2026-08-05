# spark examples

Assertion examples and supporting helpers extracted from the `spark` branch.

`SparkLendOraclePriceGuardAssertion` is unavailable and registers no triggers until collateral
disablement, outgoing transfer finalization, and risk-increasing eMode transitions are covered.

## Build

```sh
FOUNDRY_PROFILE=spark forge build
```

## Files

- SparkLendOraclePriceGuardAssertion.sol
- SparkSLLInflowStopgapAssertion.sol
- SparkVaultAssertion.sol
- SparkVaultHelpers.sol
- SparkVaultInterfaces.sol
