# Fluid (Instadapp) examples

Credible Layer assertion examples for [Fluid](https://instadapp.io/product/fluid)
([fluid-contracts-public](https://github.com/Instadapp/fluid-contracts-public)).

Fluid is built around a single **Liquidity Layer** that custodies every token for every protocol on
top of it (the lending **fTokens** and the borrow/collateral **Vaults**). The assertions here cover
two angles the user asked for:

1. **Business-logic invariants** — the core accounting facts the protocol must never violate.
2. **Assertions that let Fluid run looser limits / riskier assets safely** — the protocol keeps its
   generous, capital-efficient on-chain limits and aggressive risk parameters, while the assertion
   enforces the tighter boundary that actually keeps the system solvent and liquidatable.

## Build

```sh
FOUNDRY_PROFILE=fluid forge build
```

## Test

```sh
FOUNDRY_PROFILE=fluid pcl test
```

## Assertions

### `FluidLiquiditySolvencyAssertion` — Liquidity Layer (business logic)

Installed on the Liquidity Layer singleton. Two transaction-end invariants, read straight from the
singleton's packed per-token storage (no resolver trust, no interest-accrual reimplementation):

- **Custody covers net supply** — `recognizedCustody(Liquidity, token) + totalBorrow >= totalSupply`
  for every monitored token, i.e. accrued protocol revenue stays non-negative. Mainnet weETH/weETHs
  custody includes Fluid's Zircuit balance, matching Fluid's resolver accounting. This is the
  protocol-wide insolvency condition; the per-operation `require`s never state it against custody.
- **Exchange prices are monotonic** — supply and borrow exchange prices only ever accrue interest, so
  any decrease across the transaction signals corrupted accounting or a malicious config-slot write.

### `FluidLiquidityFlowBreakerAssertion` — Liquidity Layer (looser limits, safely)

A tiered rolling-window outflow circuit breaker (built-in `watchCumulativeOutflow`). Fluid's on-chain
withdraw/borrow limits auto-expand and are intentionally generous; this assertion lets them stay loose
while capping the *aggregate* bleed so an exploit cannot drain a market by chaining many individually
valid `operate` calls:

- **Warning tier (10% / 24h)** — block new borrows of the breached token; suppliers can still
  withdraw and borrowers can still repay, so honest exit and de-risking stay open.
- **Critical tier (20% / 24h)** — hard-pause the singleton.

The breaker intentionally rejects native-token markets and known Fluid external-custody tokens,
because the built-in ERC20 outflow watcher cannot correctly classify those custody moves.

### `FluidVaultRiskConfigAssertion` — Vault (riskier collateral, safely)

Installed on a Fluid Vault. Re-checks the vault's stored risk-parameter ordering at transaction end —
`collateralFactor < liquidationThreshold < liquidationMaxLimit`,
`liquidationMaxLimit <= 100%`, and `liquidationMaxLimit + liquidationPenalty <= 99.7%` — regardless of
how the config was written (setter, faulty upgrade, storage collision). The vault admin module only
enforces this ordering inside its setters; the assertion guarantees it in the actual stored state.
That makes it safe to tune aggressive parameters for riskier collateral: governance can push CF/LT
high, and the invariant that keeps every position liquidatable is enforced on-chain.

### `FluidFTokenSharePriceAssertion` — fToken (business logic)

Installed on an fToken (fUSDC, fWETH, ...). An fToken supplies all of its underlying into the Liquidity
Layer and its share price is yield-only by construction, so a fixed-share `convertToAssets(1e12)`
sample must never decrease across a transaction. A drop signals a loss, mispriced mint/redeem, or
accounting bug.

## Files

- `FluidInterfaces.sol` — minimal Fluid surfaces (Liquidity `operate`, vault resolver getter, fToken ERC-4626).
- `FluidLiquidityHelpers.sol` — `FluidLiquidityBase`: packed-storage decode (slots, BigMath) and calldata helpers.
- `FluidLiquiditySolvencyAssertion.sol`
- `FluidLiquidityFlowBreakerAssertion.sol`
- `FluidVaultRiskConfigAssertion.sol`
- `FluidFTokenSharePriceAssertion.sol`

## Notes

- Storage slots / bit offsets are from Fluid's `liquiditySlotsLink.sol`, `bigMathMinified.sol`, and the
  vault admin module. Exchange-price and total-amount totals use the singleton's *stored* prices, which
  form a self-consistent snapshot against the held balance.
- `watchCumulativeOutflow`'s live firing is driven by the executor's rolling-window accounting and is
  not simulated by local `pcl test`, so the flow breaker's warning-tier policy is unit-tested through a
  pure helper (`_operateBorrowsToken`) rather than an armed `cl.assertion` call.
- Native-token markets (`0xEeee...EEeE`) are skipped by the ERC20 custody check; the exchange-price check
  still applies to them.
