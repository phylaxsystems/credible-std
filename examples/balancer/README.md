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

This profile is part of the Solidity Test CI examples matrix, so the suite is gated on every PR.

## Files

- `BalancerV3VaultAssertion.sol` — per-pool protections inside the singleton Vault:
  - `assertSwapPreservesPoolInvariant` (call-scoped on `Vault.swap`, hookless pools only): the
    pool's own `computeInvariant` over live balances may not decrease across a swap beyond an
    absolute rounding-dust allowance, the fee-adjusted live tokenOut balance may not increase,
    and every registered rate observed at swap start remains within the drift bound of its
    pre-transaction baseline (so a rate transiently moved between calls and restored before
    tx-end is caught at the operation that consumed it). Pools with
    before/after-swap hooks are skipped through immutable deployment configuration: those hooks
    are intentionally reentrant in V3 and call-boundary snapshots cannot isolate the core swap,
    so hooked pools need a pool-specific variant. Because the invariant is recomputed by the
    pool's own math, this detects inconsistency between `onSwap` and `computeInvariant` (an
    honest-but-buggy pool), not a
    deliberately malicious pool that keeps both consistent — that class needs pinned
    factory/codehash combinations plus independent invariant math per pool type.
  - `assertPoolAccountingWithinVaultCustody` (tx-end): real ERC20 custody ≥ global Vault
    reserves ≥ watched pool balances + accrued aggregate protocol fees. A necessary but NOT
    sufficient bound: reserves are one global ledger shared by every pool and ERC-4626 buffer,
    so one pool's view cannot prove aggregate solvency.
  - `assertTokenRatesWithinDriftBound` (tx-end): rate-provider rates feeding pool math stay
    nonzero and within a configured bps bound across transactions that change the watched
    pool's accounting. Scoped so the provider never becomes a liveness dependency of unrelated
    Vault traffic, and skipped when the pool is in recovery mode (recovery exits deliberately
    avoid rate calls, and a broken provider must not block them). Providers already registered
    pre-transaction must present a nonzero pre-tx baseline — a successful zero is a failure,
    not a registration exemption; only providers first registered within the transaction (pool
    deployment flow) skip the drift comparison.
- `BalancerV3VaultHelpers.sol` — fork-aware Vault/pool reads and lean swap-calldata access.
- `BalancerV3VaultInterfaces.sol` — minimal mirrors of Balancer V3 Vault/pool/rate-provider types.
- `BalancerV3VaultOutflowAssertion.sol` — rolling-window circuit breaker on a token's NET outflow
  (`cumulativeOutflow - cumulativeInflow`, per the executor's `watchCumulativeOutflow` semantics)
  from Vault custody, flow-based drain protection across all pools at once.

## Notes

- The Vault is the assertion adopter for every contract in this bundle; swaps in pools other
  than the watched pool are filtered out by decoding the swap calldata, and the outflow breaker
  verifies the configured Vault against the actual adopter before tripping.
- Hook classification and thresholds (absolute invariant rounding dust, rate drift bps, outflow
  cap/window) are constructor parameters that need per-deployment calibration. Balancer fixes
  hook wiring at pool registration, so the assertion records whether before/after-swap hooks are
  enabled once instead of paying for a full hook-config read on every swap. The invariant dust
  tolerance is absolute (18-decimal invariant units) because a bps-of-invariant tolerance cannot
  express rounding dust without also allowing material repeatable loss. The outflow constructor mirrors
  the executor's trigger constraints (threshold strictly below 100%, window between the
  10-second bucket and `uint64` max) so misconfigurations surface at deploy time instead of at
  trigger registration.
- The outflow breaker thresholds NET flow and is value-blind: inflows from any pool or buffer
  offset exits, and a canonical ERC-4626 buffer wrap counts fully as outflow of the underlying.
  Calibrate above the largest legitimate single-window net outflow (whale exits, buffer
  rebalances, and `collectAggregateFees`, which transfers the whole accrued fee ledger in one
  indivisible call).
