# lighter examples

Runtime Credible Layer assertions for Lighter's L1 bridge / rollup contract (`ZkLighter`, the proxy
at `0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7` on Ethereum mainnet).

Lighter is an app-specific ZK validity rollup whose single proxied contract is simultaneously the
funds-custody bridge and the rollup state machine: a `committed -> verified -> executed` batch
pipeline, a parallel priority-request queue for L1->L2 deposits / forced transactions, and a
14-day-expiry escape hatch ("desert mode").

Every invariant here is one the contract structurally cannot enforce against itself. Each entry
point only guards its own local transition with `require`s; nothing asserts the cross-storage
relationship as a postcondition, and the trusted validator set / upgradeable proxy can write the
counters and state root directly — bypassing those local guards.

## Invariants

- **Batch & priority ordering** (`assertBatchOrdering`) — `executed <= verified <= committed` for
  both batches and priority requests, and the open queue covers every committed-but-unexecuted
  request. You cannot execute (pay out) funds against state that was never proven.
- **Finality non-decrease** (`assertFinalityNonDecreasing`) — verified/executed counters never roll
  back. Finalized funds cannot be un-finalized by a too-deep revert or a counter-rewinding upgrade.
- **State-root continuity** (`assertStateRootContinuity`) — the executed state root changes only when
  executed batches advanced, or via the proof-gated one-shot migration call. Any other root mutation
  is an operator silently rewriting account balances.
- **Desert-mode integrity** (`assertDesertModeIntegrity`) — the escape hatch is irreversible and
  freezes the operator (no commit/verify/execute) while users are exiting.

The funds-custody outflow rate limit is a separate, independently deployable assertion:

- **Collateral outflow circuit breaker** (`LighterOutflowCircuitBreaker`) — collateral custody cannot
  drain past a rolling-window TVL fraction during normal operation; the breaker stands down in desert
  mode so it never blocks the mass exits the escape hatch exists to enable. Deploy one instance per
  watched ERC-20 token.

## Files

- `src/RollupBridgeStateMachineAssertion.sol` — reusable base for zkSync-lineage rollup bridges
  (ordering, finality, state-root continuity).
- `src/LighterBridgeInterfaces.sol` — minimal `IZkLighterLike` read surface.
- `src/LighterBridgeHelpers.sol` — fork-aware reads.
- `src/LighterBridgeAssertion.sol` — state-machine + desert-mode bundle (trigger wiring + invariants).
- `src/LighterOutflowCircuitBreaker.sol` — standalone rolling-window collateral outflow breaker.
- `test/LighterBridgeAssertion.t.sol` — honest + malicious behavior per state-machine invariant.
- `test/LighterOutflowCircuitBreaker.t.sol` — breaker decision logic + constructor guards.

## Build & test

```sh
FOUNDRY_PROFILE=lighter forge build
FOUNDRY_PROFILE=lighter pcl test
```

## Deployment notes

- `IZkLighterLike` assumes each value is reachable through a same-named public getter. Verify the
  selectors/storage layout against the live deployment; if these are non-public variables, read the
  storage slots with `ph.loadStateAt` instead and adjust `LighterBridgeHelpers`.
- `LighterOutflowCircuitBreaker` uses the `watchCumulativeOutflow` trigger, which is driven by the
  executor's rolling-window accounting and is not fired by local `pcl test`. Its breach path therefore
  cannot be armed via `cl.assertion` locally (the trigger never fires, so the harness would report
  "0 executed"). The breaker's decision policy lives in the pure `_breakerTrips` function and is
  unit-tested directly, alongside its constructor guards; the trigger-fired path is validated by the
  executor in production. The four state-machine / desert-mode invariants have honest + malicious
  `pcl test` coverage.
