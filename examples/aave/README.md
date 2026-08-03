# aave examples

Assertion examples and supporting helpers extracted from the `aave` branch.

## Availability

The v4 Hub and Spoke wrappers are quarantined and register no triggers. Their fixed scan bounds
can become governance liveness limits even though upstream reserve/spoke creation has no matching
cap. V3/v4 tolerance configuration rejects 10,000 bps because that value disables ratio checks.

## Build

```sh
FOUNDRY_PROFILE=aave forge build
```

## Files

- AaveV3HorizonHelpers.sol
- AaveV3HorizonInterfaces.sol
- AaveV3HorizonOracleAssertion.sol
- AaveV3HorizonReserveBackingAssertion.sol
- AaveV4Helpers.sol
- AaveV4HubAccountingAssertion.sol
- AaveV4Interfaces.sol
- AaveV4SpokeRiskAssertion.sol
