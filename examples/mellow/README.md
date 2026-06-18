# mellow examples

Credible Layer assertions for **Mellow vaults** (the `flexible-vaults` / Core Vaults line:
`Vault` modules + `Subvault`s + `RiskManager` + `Oracle` + redeem/deposit queues), scoped
deliberately to **one threat model**:

> Bound the blast radius of a **compromised curator key** (or a buggy/rogue adapter), using
> on-chain, per-transaction invariants the protocol's own `require`s do not already express.

## Why this narrow scope

Mellow vaults are a poor fit for most generic vault assertions, and that is by design — not a gap
to fill:

- **Collateral value lives off-chain.** Subvaults hold EigenLayer/Symbiotic restaking positions.
  Their true worth (slashing, unbonding, rewards) is reconciled in via an oracle report; slashing
  produces no transaction on the vault path, so there is nothing to trigger on. Assertions cannot
  hedge restaking risk, and these do not try.
- **The hot path is permissioned by design.** Withdraw / unwind / settle / balance-correction are
  curator actions. Bounding a *legitimately authorized* action either restates the protocol's role
  check (no value) or bricks honest operations during an incident (negative value).

So the only angle with genuine value-add is insurance against a **stolen privileged key** or a
**runaway drain** — competing with timelocks/multisigs, not with a valuation oracle. Every assertion
here is justified under that one model, and every threshold is a **blast-radius cap calibrated above
the largest legitimate flow**, not a tight detector. A bound that trips during a real incident (a
slashing-driven report drop, a large legitimate batch settlement) is worse than no bound.

## Build & test

```sh
FOUNDRY_PROFILE=mellow forge build
FOUNDRY_PROFILE=mellow pcl test
```

Each assertion ships pass-and-trip `CredibleTest` coverage under `test/`, with one mock knob per
failure mode so each test trips exactly one invariant and revert reason. The `watchCumulativeOutflow`
breaker is executor-driven and not simulated by local `pcl test`, so its hard-revert decision is
exercised by a direct call; everything else uses `registerFnCallTrigger` / `registerTxEndTrigger`
and is fully simulated.

## A note on restricting *which* market actions a subvault may take

This is already enforced on-chain and is **not** re-implemented here. Every market call a subvault
makes runs through `Subvault.call → Verifier.verifyCall`, which requires the caller to hold
`CALLER_ROLE` and the `(who, where, selector[, calldata])` to be in the Verifier's on-chain
allowlist / Merkle root / custom verifier (`ERC20Verifier`, `BitmaskVerifier`, `SymbioticVerifier`,
`EigenLayerVerifier`). So "this subvault may only deposit into Aave pool X" is configured in the
Verifier — an assertion that re-checks it would only restate the protocol.

What the Verifier does **not** check is the *state of the market* it authorizes a call into: an
approved `supply` can still land in a reserve borrowed down to near-100% utilization, and Aave does
not guard that at deposit time (illiquidity only bites on withdraw). `MellowSubvaultAllocationAssertion`
fills that gap. (The Verifier's own allowlist being widened by a stolen `SET_MERKLE_ROOT_ROLE` key is
a separate blind spot — a `merkleRoot` freeze in the spirit of `MellowConfigLockAssertion` is the
companion, listed under next steps.)

## Assertions

Five focused assertions, each adopted by a different contract because each defends a different
curator-power surface. Signatures and selectors are taken from `mellow-finance/flexible-vaults`.

### `MellowVaultOutflowAssertion` — adopter: the `Vault` (deposit-asset custody)

| Invariant | Failure point covered |
|---|---|
| Cumulative deposit-asset outflow from the vault may not exceed a configured fraction of balance within a rolling window (`watchCumulativeOutflow`, hard breaker) | catastrophic single-window theft — a stolen key or runaway adapter cannot move the asset out faster than the rate limit, regardless of which curator-gated function it uses |

The flagship breaker, and the most defensible single assertion, because it is **asset-flow based,
not role based** — it survives a key that passes every role check. It counts *all* asset exits from
the vault, including legitimate reallocation into subvaults, so the threshold must sit above the
largest legitimate single-window outflow (largest planned reallocation + the largest `handleBatches`
settlement that can land in one window). A destination-aware variant (exempt transfers to known
subvaults) is a documented next step.

### `MellowOracleReportGuardAssertion` — adopter: the `Oracle`

| Invariant | Failure point covered |
|---|---|
| A single `submitReports` call may not move any supported asset's `priceD18` (the vault's price-per-share) by more than an **immutable** cap; bootstrap and protocol-flagged-suspicious reports are skipped | a stolen key repricing the vault discontinuously in one transaction — even after widening the mutable `securityParams` cap that the protocol's own check relies on |

Not a restatement of the protocol's guard: Mellow's `Oracle` already rejects reports beyond
`securityParams.maxRelativeDeviationD18` — but those params are **mutable** and bounded only by
"non-zero", so a holder of `SET_SECURITY_PARAMS_ROLE` can widen the cap in one call and reprice in
the next. This assertion's cap is fixed at adoption and cannot be widened from on-chain state.
It is a **catastrophe cap, not a manipulation detector** — a real slashing repricing is a legitimate
large negative move, so set it generously (e.g. 5000 bps).

### `MellowRiskManagerBalanceAssertion` — adopter: the `RiskManager`

| Invariant | Failure point covered |
|---|---|
| A single `modifyVaultBalance` / `modifySubvaultBalance` call may not change the tracked (sub)vault share balance by more than `max(absoluteFloor, bps × |pre-balance|)` | a stolen `MODIFY_*_BALANCE_ROLE` key zeroing or inflating vault accounting in one call |

These "trusted balance corrections" are bounded by the protocol **only in the positive direction**
(the `LimitExceeded` check fires solely when `change > 0`); a negative correction draining the
accounted balance is completely unbounded on-chain. This adds the missing magnitude bound in both
directions, relative to the pre-call balance with an absolute floor so corrections on a near-zero
balance are still possible.

### `MellowConfigLockAssertion` — adopter: the `Vault` (a `TransparentUpgradeableProxy`)

| Invariant | Failure point covered |
|---|---|
| The vault's wired `oracle` / `shareManager` / `feeManager` / `riskManager` must match the expected addresses after every transaction (per-field opt-in) | swapping the price source or mint/burn authority for an attacker-controlled contract |
| The EIP-1967 implementation and admin slots must be unwritten during the transaction | a rogue proxy upgrade swapping the entire vault logic in one call |

The trust-graph addresses have no on-chain setter in flexible-vaults — the only way to change one is
an upgrade or a storage collision — so a post-transaction value check is a strong, refactor-proof
invariant. A *legitimate* governance upgrade is exactly what trips this; run planned upgrades with
the assertion disarmed.

### `MellowSubvaultAllocationAssertion` — adopter: a `Subvault`

| Invariant | Failure point covered |
|---|---|
| A transaction that grows the subvault's supplied position in the watched lending market must leave the market holding ≥ `minExitLiquidityBps` of the new position in immediately-withdrawable liquidity | a curator (honest, careless, or compromised) parking vault funds in a market borrowed dry — an allocation the Verifier permits and Aave accepts, but that cannot be unwound on demand |

Reducing or holding the position is always allowed; only *adding* exposure into an illiquid market
trips. Supplied position and withdrawable liquidity are read as plain ERC-20 balances (the supply
receipt's `balanceOf(subvault)` and the underlying balance the receipt custodies), so it works for
any Aave-v3-like reserve without decoding pool internals. Deploy one instance per watched
`(asset, market)` pair; it deliberately does not assess restaking subvaults, whose health is
off-chain. This guards market *state* — the complement to the Verifier, which guards market *actions*.

## Binding to a concrete deployment

Everything protocol-specific is constructor configuration; resolve addresses, the deposit asset, and
real flow sizes from the target deployment before setting thresholds. Suggested starting points
(calibrate against the deployment's real reallocation/batch sizes — these are illustrative, not
final):

- **Outflow breaker:** `outflowThresholdBps = 2_000` over `outflowWindowDuration = 1 days`, raised
  above the largest legitimate single-day reallocation + settlement.
- **Oracle drift cap:** `maxReportDriftBps = 5_000` (a 50% catastrophe threshold, above the worst
  realistic single-report slashing move).
- **Balance correction:** `maxModifyBps = 2_000` with `absoluteFloorShares` set to the largest
  correction expected on a near-zero balance.
- **Config lock:** pass the deployment's `oracle` / `shareManager` / `feeManager` / `riskManager`
  to lock them (or `address(0)` to leave a field unchecked).
- **Subvault allocation:** `minExitLiquidityBps = 10_000` (the full position must stay withdrawable),
  per watched `(asset, aToken)` market, applied to each subvault that allocates into a lending market.

## Scope and limitations

- **Blast-radius caps, not detectors.** None of these value restaking positions, detect oracle
  manipulation, or improve on a timelock for *authorized* curator actions. They cap how much damage
  a stolen key can do in one transaction / window.
- **Outflow breaker is destination-blind and executor-driven.** It counts subvault reallocations as
  outflow, so calibrate generously; it is not simulated by local `pcl test`.
- **Oracle guard skips bootstrap/suspicious reports.** The first report for an asset and any
  protocol-flagged-suspicious report do not propagate to vault accounting, so they are not bounded.
- **Config lock trips on legitimate upgrades.** Disarm during planned governance upgrades.
- **Adopter scope.** Each assertion only fires for transactions that touch its adopter; deploy all
  four to cover the full curator-power surface (`Vault`, `Oracle`, `RiskManager`).

## Files

- src/MellowVaultOutflowAssertion.sol
- src/MellowOracleReportGuardAssertion.sol
- src/MellowRiskManagerBalanceAssertion.sol
- src/MellowConfigLockAssertion.sol
- src/MellowSubvaultAllocationAssertion.sol
- src/MellowCuratorHelpers.sol — shared fork reads, calldata decode, signed-int math
- src/MellowCuratorInterfaces.sol — minimal `Oracle` / `RiskManager` / vault-config surfaces + selectors
- test/MellowMocks.sol — shared mocks (oracle / risk manager / vault proxy / subvault / token), one knob per failure mode
- test/MellowVaultOutflowAssertion.t.sol
- test/MellowOracleReportGuardAssertion.t.sol
- test/MellowRiskManagerBalanceAssertion.t.sol
- test/MellowConfigLockAssertion.t.sol
- test/MellowSubvaultAllocationAssertion.t.sol

## Next steps

- Verifier permission-set freeze (adopter = a subvault's `Verifier`): lock `merkleRoot` and the
  on-chain compact-call allowlist against change within a tx, defending the action allowlist from a
  stolen `SET_MERKLE_ROOT_ROLE` / `ALLOW_CALL_ROLE` key
- Destination-aware outflow breaker (exempt transfers to connected subvaults)
- `handleBatches` payout-vs-burn consistency at the governing report price (lower priority — it
  trusts the report price, which the oracle guard already caps)
