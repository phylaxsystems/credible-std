# Anomaly-Gated Assertions

Generic damage heuristics gated behind the anomaly model. The model is a recall-first trigger: it scores every transaction touching a watched contract for how anomalous it looks, and over-fires by design, so it is not a blocking signal on its own. An anomaly-gated assertion fires on the score, then requires a deterministic damage check to confirm before it reverts. The gate drops the check's false positives (a benign whale withdrawal is not anomalous), and the check drops the model's (an anomalous-but-harmless transaction confirms nothing).

The parameters are the only per-deployment difference. No per-protocol code is needed for the generic heuristics; a protocol-specific invariant is folded in through one override.

## The disposition

Over the anomaly bit `a = score >= anomalyThresholdBps` and the enabled damage set `H`:

| | H confirms | H silent |
| --- | --- | --- |
| **a** | block (revert) | alert (the exclusive set) |
| **not a** | pass (the benign whale) | pass (normal traffic) |

`block = a AND H`, `alert = a AND NOT H`, `pass = NOT a`. The assertion implements this in control flow: the gate returns early on `NOT a`, a corroborated check reverts, and the fall-through with no revert is the alert cell, which the executor reads off-chain from a score with no invalidation. The alert cell does not revert, so a benign-but-unusual transaction is not blocked on the model score alone.

## Contracts

- `AnomalyGatedBaseAssertion`: the target, the operating threshold, the `_anomalous()` gate, and the corroboration primitives every heuristic shares (`_drains`, `_upgraded`, `_accountingBroke`, `_oracleDeviated`).
- `AnomalyGatedOutflowAssertion`, a **drain**: net outflow of a reserve token from the fund-holding contract, at or above a fraction of its pre-tx balance.
- `AnomalyGatedUpgradeAssertion`, an **upgrade**: an EIP-1967 implementation/admin slot, or a named owner slot, changed on the watched contract (the anomaly focal by default, or a named `upgradeTarget` such as a custody proxy).
- `AnomalyGatedAccountingAssertion`, an **accounting break**: an ERC-4626 share price moved beyond tolerance.
- `AnomalyGatedOracleAssertion`, an **oracle deviation**: an oracle answer moved beyond tolerance across the transaction.
- `AnomalyCompositeAssertion`: several heuristics under one operator (AND or OR) in one function, plus a protocol-specific extension leg.

## How to use it

### The composite, parameters only (the common case)

Deploy `AnomalyCompositeAssertion` with a `Config`. Enable the heuristics the protocol needs and pick the operator. The threshold is the model's recommended `threshold_bps` for your false-positive budget (see `developing-anomaly-triggers.md`).

```solidity
// A lending pool: block when an anomalous tx drains the reserve OR rewrites a proxy slot.
AnomalyCompositeAssertion.Config({
    target: pool,                 // the watched contract the model scores
    anomalyThresholdBps: 205,     // the calibrated operating point (a 2% probability)
    requireAll: false,            // OR: either heuristic blocks
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

A `Config` with no heuristic enabled reverts at deploy (`NoHeuristicEnabled`) unless `bareGateBaseline` is set: with nothing to corroborate, the assertion would block on the score alone and inherit the model's recall-first flag rate. Setting the flag is the explicit opt-in for that deployment, used only to measure the baseline. An enabled leg missing a parameter it reads also reverts at deploy (`HeuristicMisconfigured`): the drain leg needs its custody address, token, and a nonzero fraction; the accounting leg its vault; the oracle leg its feed and a selector-sized query. Deploying such a leg would ship it silently inert or falsely blocking. The base constructor rejects a zero `target` (`ZeroTarget`) and a threshold outside `[1, 10_000]` (`ThresholdOutOfRange`) for the same reason: a zero target or an over-range threshold can never gate, and a zero threshold gates on unscored contracts. The mixins enforce the same checks in their constructors.

The oracle query is full calldata: `abi.encodeWithSignature("latestAnswer()")` for a Chainlink-style feed, or `abi.encodeWithSignature("getAssetPrice(address)", asset)` for an asset-priced feed.

### À la carte, by inheritance

Inherit the mixins you want and register each trigger in `triggers()`. Several mixins compose as OR (any revert invalidates).

```solidity
contract MyGuard is AnomalyGatedOutflowAssertion, AnomalyGatedUpgradeAssertion {
    constructor(address pool, address token)
        AnomalyGatedBaseAssertion(pool, 205)
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

## Operating point

The threshold is not a round number. Each model emits a `threshold_bps` calibrated to a false-positive budget; start there and tighten. Gate below it and you inherit the recall-first flag rate. A contract too new to have a model fails open (`anomalyContext` reads 0), so the gate does not fire. Run the checks unconditionally on a fresh contract, and gate them where the contract has history.

## Testing

Released `pcl` does not implement the anomaly precompile or a score cheatcode, so the tests in `test/protection/anomaly/` fire the assertions from a tx-end trigger and override the virtual `_anomalous()` gate to drive the disposition. That exercises the corroboration and operator logic: the composite's dispositions in `AnomalyCompositeAssertion.t.sol`, and each single-heuristic mixin (plus the `MyGuard` composition above) in `AnomalyGatedMixinAssertions.t.sol`. The score-to-gate wiring and the false-positive rate are validated by the executor's own tests and by backtesting against the real model; see `developing-anomaly-triggers.md` in the anomaly-detection repo.

## What it does not do

These are generic effect checks. They do not model bespoke protocol logic; that is the `_extra` leg or a hand-written assertion. They also do not bound a slow drain across transactions; pair them with a cumulative-outflow circuit breaker (`protection/vault/ERC4626CumulativeOutflowAssertion`) for a rolling-window limit.
