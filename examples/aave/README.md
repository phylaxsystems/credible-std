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

## Aave v3 Horizon oracle guard

`AaveV3HorizonOracleAssertion` checks the exact `AaveOracle.getAssetPrice`
returns consumed by successful risk-sensitive Pool operations against per-asset
PreTx baselines. It also rejects temporary provider, source, and fallback
changes, including configuration writes restored before transaction end.

Deployment must configure an `AssetPolicy` for every active reserve whose price
the Pool can consume. Policies with zero deviation require exact same-transaction
price stability; nonzero tolerances should be asset-specific and empirically
calibrated. `maxTraceCalls` is a fail-closed bound on traced provider, oracle, and
source calls.

The source/fallback storage guards are pinned to the Aave v3.3 `AaveOracle`
layout (`assetsSources` mapping slot 0 and `_fallbackOracle` slot 1). Re-verify
those slots before adopting the assertion against a different oracle
implementation or storage layout.
