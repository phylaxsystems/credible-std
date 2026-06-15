# lido examples

Generic Credible Layer assertions for **Lido stETH vaults** — any vault that custodies
ETH/stETH/wstETH, optionally allocates it into an Aave v3-like lending market (typically a looped
wstETH-collateral / WETH-debt position), and prices its shares through some rate source.

This covers the whole family of stETH vaults — Lido Earn's GGV (Veda BoringVault), its EarnETH
successor (Mellow flexible-vaults), comparable third-party stETH loopers, and Lido V3 stVaults —
without binding to any one stack's function selectors. Every invariant is expressed at transaction
boundaries (`registerTxEndTrigger` + pre/post-tx fork reads) or as a rolling cumulative-flow
trigger, so the suite only needs addresses and thresholds to deploy against a concrete vault.

## Build

```sh
FOUNDRY_PROFILE=lido forge build
```

## The headline ask: keep stETH withdrawable back to Lido

The concrete thing Lido asked for is a flow restriction: **some share of a vault's stETH must
always stay in a state where it can be withdrawn back to Lido — never fully locked or deployed.**
`LidoStEthExitBufferAssertion` is that invariant. Before reading it, two facts about Lido
withdrawals bound what any on-chain assertion can honestly promise:

### Requestable vs claimable — what "withdrawable at any time" can actually guarantee

Unstaking stETH is a two-step, non-atomic process:

1. **Request** — burn stETH/wstETH against Lido's `WithdrawalQueueERC721`, receive an NFT. This is
   permissionless and available any time, but **capped at 1,000 ETH per request** (min 100 wei);
   larger exits must be split into batched requests, and a request **cannot be canceled**.
2. **Claim** — once the request is finalized, redeem the NFT for ETH. Finalization is bounded by
   the **Ethereum validator exit queue** plus Lido's own buffer — on the order of tens of thousands
   of ETH/day protocol-wide, varying with network conditions. It is *not* instant.

So "withdrawable back to Lido at any time" can be guaranteed only in the **requestable** sense:
the vault always holds enough stETH-equivalent in idle (un-deployed) form to *submit* to the queue
immediately. **Claimable-instantly cannot be guaranteed by a per-vault assertion** — claim
throughput is a Lido-protocol-global property, not something a vault's state can promise. This
suite enforces requestability and is explicit about that boundary; pretending otherwise would be
dishonest to the adopter.

The assertion therefore protects two things, configurable independently:

- a **standing buffer floor** — idle stETH-equivalent (idle stETH + idle wstETH at `stEthPerToken`)
  must stay above a floor on *every* transaction, so the vault is provably never fully deployed and
  always has a position to request against;
- a **cumulative outflow circuit breaker** — stETH/wstETH cannot leave the vault faster than a
  configured fraction of balance per rolling window. This is the **Safe last-mile defense**: even
  if the vault's entire signer pipeline is compromised (the Bybit failure mode), a burst drain
  trips the breaker and the transaction is never included.

### How existing stETH vaults reserve exit liquidity (survey)

The buffer-floor design follows established practice for vaults whose underlying is non-atomic to
exit:

| Pattern | How it reserves exit liquidity | Relevance |
|---|---|---|
| **ERC-4626** (`maxWithdraw`/`maxRedeem`) | Assumes *atomic* underlying liquidity; `maxWithdraw` returns whatever is currently idle, silently capping large exits | Works only while a buffer happens to exist — there's no *floor*, which is the gap this assertion fills |
| **ERC-7540** async request/claim | Models exactly the stETH case: a `requestRedeem` → `claim` two-step for non-atomic underlyings | The on-chain analogue of Lido's request/claim; the "requestable" semantics here mirror it |
| **Yearn v3, Morpho, Pendle** withdrawal buffers | Hold an explicit idle reserve (a % of TVL) sized so routine redemptions never touch deployed positions | This is the buffer floor, made into an enforced invariant rather than a strategist convention |
| **Aave stETH markets** | No vault-level buffer; exit liquidity is the reserve's un-borrowed balance, drainable by any borrower | Why the risk suite's exit-liquidity guard checks the reserve *and* the vault keeps its own floor |

The takeaway: production stETH vaults already reserve exit liquidity, but as an off-chain policy a
compromised or careless strategist can erode. The buffer floor turns that policy into an invariant
the block builder enforces at inclusion time.

## Assertions

### `LidoStEthExitBufferAssertion` — adopter: the vault (the account custodying stETH/wstETH)

| Invariant | Failure point covered |
|---|---|
| Buffer floor: after every transaction the vault's idle, requestable stETH-equivalent (idle stETH + idle wstETH at the Lido rate) must be ≥ the larger of an absolute minimum and a configured fraction of total stETH-equivalent (idle + deployed) | stETH is provably never fully locked/deployed — a withdrawal request to Lido can always be submitted |
| Outflow circuit breaker: cumulative stETH and wstETH outflow from the vault may not exceed a configured fraction of balance within a rolling window (`watchCumulativeOutflow`, hard breaker) | burst drains — a compromised signer pipeline (Safe last-mile) cannot move stETH out faster than the rate limit |

The floor caps the absolute minimum at the vault's total stETH-equivalent, so a vault smaller than
the floor is required to keep *everything* idle rather than being bricked. The two layers compose:
the floor stops over-*deployment* while stETH is held, the breaker stops *draining* it out entirely.
For the full "never fully deployed and never drained" guarantee, configure both.

### `LidoStEthVaultRiskAssertion` — adopter: the contract that moves the position

(the vault itself, or its manager/strategy executor when allocations run through one)

| Invariant | Failure point covered |
|---|---|
| Reduce-only regime: when the pre-tx health factor is below the comfort band, stETH trades off peg, the rate source can't report a rate, or the collateral reserve is no longer liquid enough for the vault to exit, a transaction may not grow debt or lower the health factor — and under market-condition triggers (shaky pricing, illiquid collateral) it may not grow the supplied position either | no new allocations into unhealthy positions; reduce-only when oracles are shaky |
| Exit-liquidity guard: a transaction that grows debt must leave the borrowed reserve holding ≥ a configured multiple of the vault's debt | underlying market health (the vault can always repay and unwind) |
| Collateral withdrawability guard: a transaction that deepens the supplied position must leave the collateral reserve holding ≥ a configured fraction of the vault's supplied collateral in un-borrowed form | the deployed leg stays withdrawable at execution time — distinct from the vault-held buffer floor above |
| Position envelope: the health factor ends every transaction above a hard floor, may only decline while staying inside the comfort band, and the raw collateral/debt ratio holds a minimum | health factor must not degrade; collateral ratio maintained |

### `LidoStEthVaultPegAssertion` — adopter: the share token (or whatever mints/burns shares)

| Invariant | Failure point covered |
|---|---|
| Supply-change depeg gate: any transaction that changes share supply — a mint or burn through any path (teller, queue, solver, direct) — reverts while the stETH/ETH market price is outside the peg band | underlying asset depeg — users cannot enter/exit at a fictional parity rate |
| wstETH rate integrity: `stEthPerToken()` must not decrease within a transaction, and the vault's wstETH rate provider (if configured) must match it within tolerance | rate-provider substitution/manipulation while shares are priced |

### `LidoStEthVaultNavAssertion` — adopter: the contract that reports the share rate

| Invariant | Failure point covered |
|---|---|
| Rate-vs-NAV: after every transaction touching the rate reporter, its `getRate()` must sit within tolerance of NAV recomputed from on-chain state (idle base asset + stETH at parity + wstETH at the Lido rate + net Aave-like position), in both directions | compromised/buggy rate updater draining value a bounded step at a time |

## How this maps to capital efficiency

Idle buffers exist because unwind-ability is normally uncertain. This suite makes unwind-ability
*provable* at execution time: the exit-buffer floor proves a withdrawal to Lido can always be
requested, the risk suite's exit-liquidity and withdrawability guards prove each new allocation is
unwindable, and the position deepens only while a reserve is liquid. With those proofs in place,
buffer sizing becomes a policy choice — a small enforced floor — instead of a worst-case guess.
The honest tail: the floor guarantees *requestable*, not *instantly claimable*; if Lido's queue is
deep, a small operational reserve above the floor still smooths same-block redemptions.

## Binding to a concrete deployment

Everything protocol-specific is constructor configuration:

- `vault` — the custody account holding idle assets and any lending position
- `stEth` / `wstEth` — the Lido tokens; wstETH is valued through `stEthPerToken()`
- `deployedStEthReceipt` — optional receipt token for stETH-equivalent deployed out of idle custody
  (e.g. Aave `awstETH`); lets the buffer floor size against total exposure, not just idle holdings
- `aavePool` / `aaveOracle` — any Aave v3-compatible market (`getUserAccountData` / `getAssetPrice`)
- `rateSource` — anything exposing `getRate()`: a Veda accountant, a Balancer-style rate provider,
  a Mellow-style oracle adapter
- `shareToken` — the vault share ERC-20 (for BoringVaults, the vault itself)
- `borrowedAsset` / `borrowedAssetReserve` / `borrowedAssetDebtToken` — the borrowed leg for the
  exit-liquidity guard (e.g. WETH / aWETH / variable-debt WETH)
- `collateralAsset` / `collateralAssetReserve` / `collateralAssetSupplyToken` — the supplied leg
  for the withdrawability guard (e.g. wstETH / awstETH / awstETH; on Aave the reserve custody and
  the receipt token are the same contract)
- `stEthEthFeed` — a Chainlink-style stETH/ETH feed (mainnet: `0x86392dC19c0b719886221c68AC0C1F0e8DB4eF14`, 18 decimals)

Optional signals disable cleanly: a zero feed disables depeg detection, a zero `rateSource`
disables the pricing-health signal, zero `minCollateralRatioBps` / `minExitLiquidityBps` /
`minBufferBps` / `outflowThresholdBps` disable those guards, a zero `aavePool` drops the position
leg from NAV, a zero `deployedStEthReceipt` sizes the buffer floor against idle holdings only.

Suggested starting thresholds for a looped stETH vault on Aave:

- **Exit buffer:** `minBufferBps = 500` (keep ≥5% requestable), `outflowThresholdBps = 5_000` with
  `outflowWindowDuration = 1 days` (no more than half the balance may leave per day — generous
  enough for routine operations, tight enough to stop a burst drain). Set `minIdleStEthEq` to a hard
  floor in stETH wei if the vault has a known minimum size.
- **Risk:** `minHealthFactor = 1.01e18` (the floor Lido itself codified in its GGV migrator),
  `reduceOnlyHealthFactor = 1.05e18`, `minExitLiquidityBps = 10_000` (full unwind must be possible),
  `minCollateralLiquidityBps = 10_000`.
- **Peg / NAV:** `maxDepegBps = 100` (1%), `rateToleranceBps = 50`.

## Scope and limitations

- **Requestable, not claimable.** The exit buffer guarantees stETH can be *submitted* to Lido's
  WithdrawalQueue at any time; finalization is bounded by the validator exit queue and the 1,000
  ETH/request cap, which no per-vault assertion controls.
- **Outflow breaker is destination-blind.** The v1 breaker is a hard rate limit on stETH/wstETH
  leaving the vault — it does not yet distinguish a legitimate large unstake-to-Lido from a drain.
  Set the window threshold generously, or split large planned exits. A destination-aware variant
  (exempt transfers to the WithdrawalQueue) is a documented next step.
- **NAV coverage.** The NAV assertion counts idle base-asset/stETH/wstETH and one Aave-like
  position. Vaults with extra legs (Morpho/Euler positions, L2-bridged capital) need either a wider
  `rateToleranceBps` or an extended `_vaultNavInBaseAt`.
- **Adopter scope.** Assertions only fire for transactions that touch their adopter. Third-party
  liquidations call the lending pool directly — pair this suite with the lending-suite assertions
  on the pool if that path matters.
- **One market per instance.** The risk assertion reads a single Aave-like pool; deploy one
  instance per market for multi-market vaults.

## Files

- LidoStEthExitBufferAssertion.sol
- LidoStEthVaultRiskAssertion.sol
- LidoStEthVaultPegAssertion.sol
- LidoStEthVaultNavAssertion.sol
- LidoVaultHelpers.sol
- LidoVaultInterfaces.sol

## Next steps

- `CredibleTest` E2E coverage (mock pool/rate-source/feed/token knobs that trip one invariant at a time)
- Destination-aware outflow breaker (exempt transfers to Lido's `WithdrawalQueueERC721`)
- Morpho/Euler position legs for the NAV and health checks
