# Spark examples

Protocol-specific assertion examples and supporting helpers.

`SparkLendOraclePriceGuardAssertion` is unavailable and registers no triggers until collateral
disablement, outgoing transfer finalization, and risk-increasing eMode transitions are covered.

## Build and test

```sh
FOUNDRY_PROFILE=spark forge build
FOUNDRY_PROFILE=spark pcl test
```

## Files

- [SparkLendOraclePriceGuardAssertion.sol](src/SparkLendOraclePriceGuardAssertion.sol)
- [SparkSLLInflowStopgapAssertion.sol](src/SparkSLLInflowStopgapAssertion.sol)
- [SparkVaultAssertion.sol](src/SparkVaultAssertion.sol)
- [SparkVaultHelpers.sol](src/SparkVaultHelpers.sol)
- [SparkVaultInterfaces.sol](src/SparkVaultInterfaces.sol)
