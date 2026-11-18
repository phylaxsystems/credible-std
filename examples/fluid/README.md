# Fluid (Instadapp) examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Credible Layer assertion examples for [Fluid](https://instadapp.io/product/fluid)
([fluid-contracts-public](https://github.com/Instadapp/fluid-contracts-public)).

Fluid is built around a single **Liquidity Layer** that custodies every token for every protocol on
top of it (the lending **fTokens** and the borrow/collateral **Vaults**). The assertions here cover
accounting checks and configurable risk policies:

1. **Business-logic invariants** — the core accounting facts the protocol must never violate.
2. **Operator policies** — flow thresholds and stored risk-parameter ordering, subject
   to the coverage and implementation limits below.

## Build

```sh
FOUNDRY_PROFILE=fluid forge build
```

## Test

```sh
FOUNDRY_PROFILE=fluid pcl test
```

This suite runs on every PR via the `examples-pcl` matrix job in
`.github/workflows/solidity-test.yml`, so a regression in these assertions fails CI.

## Assertions

### `FluidLiquiditySolvencyAssertion` — Liquidity Layer (business logic)

Installed on the Liquidity Layer singleton. The registered transaction-end check
requires persisted supply and borrow exchange prices to be non-decreasing for
each configured token.

Despite the contract name, it does **not** check custody against net supply. That
check was removed because newly written totals can coexist with older persisted
prices after a legitimate operation, producing a false insolvency signal.

### `FluidLiquidityFlowBreakerAssertion` — Liquidity Layer flow policy

A tiered rolling-window outflow circuit breaker (built-in `watchCumulativeOutflow`). Fluid's on-chain
withdraw/borrow limits auto-expand and are intentionally generous; this assertion lets them stay loose
while capping the *aggregate* bleed so an exploit cannot drain a market by chaining many individually
valid `operate` calls:

- **Warning tier (10% / 24h)** — block new borrows of the breached token; suppliers can still
  withdraw and borrowers can still repay, so honest exit and de-risking stay open.
- **Critical tier (20% / 24h)** — hard-pause the singleton.

The breaker intentionally rejects native-token markets and known Fluid external-custody tokens,
because the built-in ERC20 outflow watcher cannot correctly classify those custody moves.

### `FluidVaultRiskConfigAssertion` — Vault configuration policy

Installed on a Fluid Vault. Re-checks the vault's stored risk-parameter ordering at transaction end —
`collateralFactor < liquidationThreshold < liquidationMaxLimit`,
`liquidationMaxLimit <= 100%`, and `liquidationMaxLimit + liquidationPenalty <= 99.7%` — regardless of
how the config was written (setter, faulty upgrade, storage collision). The vault admin module only
enforces this ordering inside its setters; the assertion guarantees it in the actual stored state.
This enforces the stated parameter relationships; it does not establish that a collateral asset,
oracle, or chosen liquidation threshold is economically safe.

### `FluidFTokenSharePriceAssertion` — fToken (business logic)

Installed on an fToken (fUSDC, fWETH, ...). An fToken supplies all of its underlying into the Liquidity
Layer and its share price is yield-only by construction, so a fixed-share `convertToAssets(1e12)`
sample must never decrease across a transaction. A drop signals a loss, mispriced mint/redeem, or
accounting bug. The check skips transactions with zero share supply at either snapshot.

## Files

- `FluidInterfaces.sol` — minimal Fluid surfaces (Liquidity `operate`, vault resolver getter, fToken ERC-4626).
- `FluidLiquidityHelpers.sol` — `FluidLiquidityBase`: packed-storage decode (slots, BigMath) and calldata helpers.
- `FluidLiquiditySolvencyAssertion.sol`
- `FluidLiquidityFlowBreakerAssertion.sol`
- `FluidVaultRiskConfigAssertion.sol`
- `FluidFTokenSharePriceAssertion.sol`

## Notes

- Storage slots / bit offsets are taken from Fluid's `liquiditySlotsLink.sol`,
  `bigMathMinified.sol`, and vault admin module; verify them against the adopted implementation.
- The flow breaker has pure `_operateBorrowsToken` tests and armed tests of the
  `matchingCalls` scan using a substitute call trigger. These tests do not exercise
  the rolling-window trigger or its `outflowContext`, so they do not validate flow accounting.
- The persisted exchange-price check supports native-token markets; the ERC-20 flow
  breaker rejects them. No custody-solvency check is registered.
