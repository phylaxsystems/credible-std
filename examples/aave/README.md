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
- AaveV4HubFlowRateCircuitBreaker.sol
- AaveV4Interfaces.sol
- AaveV4OracleConsumptionAssertion.sol
- AaveV4OracleConsumptionHelpers.sol
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

## Aave v4 consumed-oracle guard

`AaveV4OracleConsumptionAssertion` checks every committed Spoke-to-AaveOracle
price return against a per-reserve PreTx envelope. It maps the exact parent
oracle output through its direct `latestAnswer()` child, rejects routing and
adapter write-and-restore sequences, validates complete reserve policy, and
uses one bounded transaction-end scan for nested and multicall flows.

`AaveV4EthereumMainSpokeOracleAssertion` pins the live Ethereum Main Spoke,
implementation, oracle, 14 reserves, direct sources, and 22 verified mutable
source-graph slots at block 25,646,732.

See the
[deployment guide](AAVE_V4_ORACLE_ASSERTION_DEPLOYMENT.md) and
[pinned research and trace analysis](research/aave-v4-oracle-consumption-protection-2026-07-30.md).

## Aave v4 flow-rate calibration

The ready-to-adopt Core and Prime Hub circuit breakers cover WBTC, USDG, and
wstETH, the three highest-TVL Aave v4 assets in the 2026-07-30 DefiLlama
snapshot. Their 24-hour cumulative-flow and 10-second peak-rate limits use a
20% buffer over the maximum observed values in the preceding 30 days.

See
[aave-v4-flow-rate-calibration-2026-07-30.md](research/aave-v4-flow-rate-calibration-2026-07-30.md)
for the block range, measurements, and operational caveats.
