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

## Deployment and attack scripts

The demo also includes script contracts under `script/`:

- `VaultDemoDeploy.s.sol` deploys the OpenZeppelin ERC20-based demo token, vulnerable/unprotected vault, protected vault, oracle, market, and curator vault. On broadcast runs, it sends only 1 wei to the configured Safe, mints demo USDM, then seeds both vaults and the market with 100 USDM from the deployer.
- `VaultDemoDeploy.s.sol` exposes assertion attachment helpers for the protected vault and curator vault. In local PCL tests, call an attachment helper immediately before the transaction that should trigger that assertion.
- `VaultDemoAttack.s.sol` sends bad transactions against deployed contracts. Set `VAULT_DEMO_ATTACK` to `unprotected-mint`, `protected-mint`, `donation`, `large-deposit`, or `curator-allocation`.

Ink mainnet deployment:

```sh
VAULT_DEMO_SAFE=0x... \
forge script examples/vault_demo/script/VaultDemoDeploy.s.sol:VaultDemoDeploy \
  --rpc-url "$INK_RPC_URL" --account phy --broadcast
```

Attack transaction example:

```sh
VAULT_DEMO_ASSET=0x... \
VAULT_DEMO_UNPROTECTED_VAULT=0x... \
VAULT_DEMO_PROTECTED_VAULT=0x... \
VAULT_DEMO_ATTACK=protected-mint \
forge script examples/vault_demo/script/VaultDemoAttack.s.sol:VaultDemoAttack \
  --rpc-url "$INK_RPC_URL" --account phy --broadcast
```

The script workflow is covered by `VaultDemoScripts.t.sol`:

```sh
FOUNDRY_PROFILE=vault-demo pcl test --offline --match-contract VaultDemoScriptsTest
```

Assertion mapping:

- Use case 1: arm `VaultAssetsMatchSharePriceAssertion` on one vulnerable vault, then call the same broken `mint` on the protected and unprotected vaults.
- Use case 2: arm `VaultConvertToAssetsOracleSanityAssertion` on the wUSDM-style vault, then call `donateAssets` to move USDM into the vault without `deposit`.
- Use case 3: arm `CuratorMarketHealthAssertion` on `CuratorVaultDemo`, then call `allocate(market, assets)` as the valid curator while the market is above 99% utilization or its oracle moves intra-transaction.
- Circuit breaker: arm `VaultCircuitBreakerAssertion` on the ERC4626 vault, then call `deposit` or `withdraw` with more than 25% of the vault's starting asset balance to trip the corresponding flow breaker.
