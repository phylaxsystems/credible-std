# Anomaly-Gated Assertions

Generic damage heuristics gated behind the anomaly model. The model is a recall-first trigger: it scores every transaction touching a watched contract for how anomalous it looks, and over-fires by design, so it is not a blocking signal on its own. An anomaly-gated assertion fires on the score, then requires a deterministic damage check to confirm before it reverts. The gate drops the check's false positives (a benign whale withdrawal is not anomalous), and the check drops the model's (an anomalous-but-harmless transaction confirms nothing).

The parameters are the only per-deployment difference. No per-protocol code is needed for the generic heuristics; a protocol-specific invariant is folded in through one override.

## The disposition

Over the anomaly bit `a = the score cleared the assertion's sensitivity level` and the enabled damage set `H`:

| | H confirms | H silent |
| --- | --- | --- |
| **a** | block (revert) | alert (the exclusive set) |
| **not a** | pass (the benign whale) | pass (normal traffic) |

`block = a AND H`, `alert = a AND NOT H`, `pass = NOT a`. The trigger and the body split this between them. `NOT a` never reaches the assertion: the trigger fires only when the score clears the level, so the whole bottom row costs no execution. Inside the body a corroborated check reverts, and the fall-through with no revert is the alert cell, which the executor reads off-chain from a score with no invalidation. The alert cell does not revert, so a benign-but-unusual transaction is never blocked on the model score alone.

A body therefore checks damage and nothing else. The level comparison happens where the model's ladder lives, so the body has no score to re-read.

## Contracts

- `AnomalyGatedBaseAssertion`: the target, the sensitivity level, the trigger registration, and the corroboration primitives every heuristic shares (`_drains`, `_upgraded`, `_accountingBroke`, `_oracleDeviated`).
- `AnomalyGatedOutflowAssertion`, a **drain**: net outflow of a reserve token from the fund-holding contract, at or above a fraction of its pre-tx balance.
- `AnomalyGatedUpgradeAssertion`, an **upgrade**: an EIP-1967 implementation/admin slot, or a named owner slot, changed on the watched contract (the anomaly focal by default, or a named `upgradeTarget` such as a custody proxy).
- `AnomalyGatedAccountingAssertion`, an **accounting break**: an ERC-4626 share price moved beyond tolerance.
- `AnomalyGatedOracleAssertion`, an **oracle deviation**: an oracle answer moved beyond tolerance across the transaction.
- `AnomalyCompositeAssertion`: several heuristics under one operator (AND or OR) in one function, plus a protocol-specific extension leg.

## How to use it

### The composite, parameters only (the common case)

Deploy `AnomalyCompositeAssertion` with a `Config`. Enable the heuristics the protocol needs and pick the operator.

`sensitivity` is a level from `Sensitivity`, 1–10, rather than a score. Each level fixes a false-positive budget; level 7, the recommended point, fires on 1% of the contract's own transactions. The threshold behind it is resolved from that contract's own history, where the trigger is evaluated, so one level means one budget on every contract and a retrain moves the threshold without touching this code.

```solidity
// A lending pool: block when an anomalous tx drains the reserve OR rewrites a proxy slot.
AnomalyCompositeAssertion.Config({
    target: pool,                       // the watched contract the model scores
    sensitivity: Sensitivity.RECOMMENDED, // level 7: fires on ~1% of this pool's transactions
    requireAll: false,                  // OR: either heuristic blocks
    bareGateBaseline: false,      // true only for a score-only baseline deploy (see below)
    useDrain: true,
    outflowTarget: aToken,        // the reserve custody contract (may differ from `target`)
    outflowToken: reserve,
    outflowFracBps: 250,          // drain >= 2.5% of the reserve
    useUpgrade: true,
    upgradeTarget: address(0),    // watch `target`; or name the custody proxy
    ownerSlot: bytes32(0),        // EIP-1967 slots only; or a named owner slot
    useAccounting: false, accountingVault: address(0), shareToleranceBps: 0,
    useOracle: false, oracle: address(0), oracleQuery: "", oracleToleranceBps: 0
})
```

`requireAll: true` blocks only when **every** enabled heuristic corroborates, e.g. a proxy that both drains and upgrades in one transaction. A fleet of single-heuristic assertions can only OR, since any revert invalidates the transaction, so an AND across heuristics and the exclusive-set fall-through have to live in one function. That is what the composite provides.

A `Config` with no heuristic enabled reverts at deploy (`NoHeuristicEnabled`) unless `bareGateBaseline` is set: with nothing to corroborate, the assertion would block on the score alone and inherit the model's recall-first flag rate. Setting the flag is the explicit opt-in for that deployment, used only to measure the baseline. An enabled leg missing a parameter it reads also reverts at deploy (`HeuristicMisconfigured`): the drain leg needs its custody address, token, and a fraction in `[1, 10_000]` (net outflow is capped by the pre-transaction balance, so a larger fraction can never corroborate); the accounting leg its vault; the oracle leg its feed and a selector-sized query. Deploying such a leg would ship it silently inert or falsely blocking. The base constructor rejects a zero `target` (`ZeroTarget`) and a sensitivity outside `[1, 10]` (`SensitivityOutOfRange`) for the same reason: a zero target can never be scored, a level above 10 names no rung of the ladder and could never fire, and level 0 is the "cleared nothing" sentinel an unscored contract reads back, accepting it would gate true on every contract the model never scored. The mixins enforce the same checks in their constructors.

The oracle query is full calldata: `abi.encodeWithSignature("latestAnswer()")` for a Chainlink-style feed, or `abi.encodeWithSignature("getAssetPrice(address)", asset)` for an asset-priced feed.

### À la carte, by inheritance

Inherit the mixins you want and register each trigger in `triggers()`. Several mixins compose as OR (any revert invalidates).

```solidity
contract MyGuard is AnomalyGatedOutflowAssertion, AnomalyGatedUpgradeAssertion {
    constructor(address pool, address token)
        AnomalyGatedBaseAssertion(pool, Sensitivity.RECOMMENDED)
        AnomalyGatedOutflowAssertion(pool, token, 250)
        AnomalyGatedUpgradeAssertion(address(0), bytes32(0))
    {}

    function triggers() external view override {
        _registerOutflowTrigger();
        _registerUpgradeTrigger();
    }
}
```

### A protocol-specific leg

Override `_extra` on the composite to fold an invariant the generic heuristics cannot express into the operator. A check derived from the protocol's own state raises detection and precision above the generic set.

```solidity
contract MyComposite is AnomalyCompositeAssertion {
    constructor(Config memory c) AnomalyCompositeAssertion(c) {}

    /// Corroborate when the protocol reports itself insolvent post-tx.
    function _extra() internal override returns (bool enabled, bool corroborates) {
        // read protocol state at _postTx(), return (true, invariantBroken)
    }
}
```

## Choosing a level

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Fires on | 0.01% | 0.02% | 0.05% | 0.1% | 0.2% | 0.5% | **1%** | 2% | 5% | 10% |

Higher is more sensitive: it catches more, and fires on more benign traffic. Start at `Sensitivity.RECOMMENDED` (level 7) and move only on a measurement.

The percentages above are budgets. What each level costs and buys **on your contract** is measured: the platform's preview returns, per level, the false-positive rate realised on that contract's own traffic and the recall estimated from exploits against protocols in the same model family. Ask for that table before choosing anything but the recommended level.

Some levels are unavailable on a given contract. A 0.01% budget needs 10,000 transactions of history behind it, so a shorter history cannot resolve the bottom of the ladder. The preview reports those levels disabled instead of estimating them, and a trigger set to one never fires.

A contract too new to have a model at all also fails open: `anomalyContext` reads `firesAt == 0`, which clears no level, so the gate never opens. Run the checks unconditionally on a fresh contract and gate them once it has history. The platform's release check refuses to ship a trigger pointed at a contract with no usable model, so production should never see this state.

## Testing

Released `pcl` does not implement the anomaly precompile, so the tests in `test/protection/anomaly/` fire the assertions from a tx-end trigger standing in for the anomaly trigger. What they cover is the damage half, which is all the body does: the composite's dispositions in `AnomalyCompositeAssertion.t.sol`, each single-heuristic mixin (plus the `MyGuard` composition above) in `AnomalyGatedMixinAssertions.t.sol`, and the drain ratio's boundaries and overflow behaviour in `AnomalyGatedBaseAssertion.t.sol`. `AnomalySensitivityGate.t.sol` pins the ladder's bounds and the constructor's refusal to deploy a level that is not on it.

Whether the trigger fires at a given level is the executor's decision, tested in its own selection suite alongside the level resolution. The false-positive rate is validated by backtesting against the real model; see `developing-anomaly-triggers.md` in the anomaly-detection repo.

## What it does not do

These are generic effect checks. They do not model bespoke protocol logic; that is the `_extra` leg or a hand-written assertion. They also do not bound a slow drain across transactions; pair them with a cumulative-outflow circuit breaker (`protection/vault/ERC4626CumulativeOutflowAssertion`) for a rolling-window limit.
