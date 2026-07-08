# balancer examples

Assertion examples for Balancer V3's singleton Vault architecture.

## Build

```sh
FOUNDRY_PROFILE=balancer forge build
```

## Test

```sh
FOUNDRY_PROFILE=balancer pcl test
```

## Files

- `BalancerV3VaultAssertion.sol` — per-pool protections inside the singleton Vault:
  - `assertSwapPreservesPoolInvariant` (call-scoped on `Vault.swap`): the pool's own
    `computeInvariant` over live balances may not decrease across a swap, BPT supply is frozen,
    and balances move in the swap's direction. The Vault trusts `onSwap`'s answer with no
    equivalent `require`.
  - `assertVaultCustodyCoversPoolAccounting` (tx-end): real ERC20 custody ≥ Vault reserves ≥
    watched pool balances + accrued aggregate protocol fees.
  - `assertTokenRatesWithinDriftBound` (tx-end): rate-provider rates feeding pool math stay
    nonzero and within a configured bps bound within one transaction.
- `BalancerV3VaultHelpers.sol` — fork-aware Vault/pool reads and lean swap-calldata access.
- `BalancerV3VaultInterfaces.sol` — minimal mirrors of Balancer V3 Vault/pool/rate-provider types.
- `BalancerV3VaultOutflowAssertion.sol` — rolling-window circuit breaker on a token leaving
  Vault custody (`watchCumulativeOutflow`), flow-based drain protection across all pools at once.

## Notes

- The Vault is the assertion adopter for every contract in this bundle; swaps in pools other
  than the watched pool are filtered out by decoding the swap calldata.
- Thresholds (invariant rounding dust, rate drift bps, outflow cap/window) are constructor
  parameters that need per-deployment calibration.
