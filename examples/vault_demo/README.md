# Vault Demo

This example contains intentionally vulnerable demo contracts for the three fault scenarios in the vault plan.

- `VulnerableERC4626Vault`: normal ERC4626 `deposit`, `withdraw`, and `redeem`, but `mint` issues shares without collecting assets.
- `VaultConvertToAssetsOracleSanityAssertion`: treats `convertToAssets(probeShares)` as the checked price and catches direct asset donations that manipulate the exchange rate.
- `CuratorMarketHealthAssertion`: blocks otherwise-authorized curator `allocate` calls when the target market utilization is above the configured threshold or its oracle deviates intra-transaction.
- `VaultCircuitBreakerAssertion`: hard-stops vault asset flow when cumulative inflow exceeds 25% over 6 hours or cumulative outflow exceeds 25% over 24 hours.

Run the demo tests with:

```sh
FOUNDRY_PROFILE=vault-demo pcl test --offline
```

Assertion mapping:

- Use case 1: arm `VaultAssetsMatchSharePriceAssertion` on one vulnerable vault, then call the same broken `mint` on the protected and unprotected vaults.
- Use case 2: arm `VaultConvertToAssetsOracleSanityAssertion` on the wUSDM-style vault, then call `donateAssets` to move USDM into the vault without `deposit`.
- Use case 3: arm `CuratorMarketHealthAssertion` on `CuratorVaultDemo`, then call `allocate(market, assets)` as the valid curator while the market is above 99% utilization or its oracle moves intra-transaction.
- Circuit breaker: arm `VaultCircuitBreakerAssertion` on the ERC4626 vault, then call `deposit` or `withdraw` with more than 25% of the vault's starting asset balance to trip the corresponding flow breaker.
