# Lighter examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Credible Layer assertion prototypes for Lighter's L1 bridge / rollup contract (`ZkLighter`, the proxy
at `0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7` on Ethereum mainnet).

> **Unavailable:** the `LighterBridgeAssertion` wrapper is quarantined and registers no triggers.
> It must bind the current proxy implementation, causally bind root changes to the executed batch,
> and validate official request expiry before desert-mode activation. The outflow circuit breaker is
> a separate operational policy and is not represented as a bridge invariant.

Lighter is an app-specific ZK validity rollup whose single proxied contract is simultaneously the
funds-custody bridge and the rollup state machine: a `committed -> verified -> executed` batch
pipeline, a parallel priority-request queue for L1->L2 deposits / forced transactions, and a
14-day-expiry escape hatch ("desert mode").

Every invariant here is one the contract structurally cannot enforce against itself. Each entry
point only guards its own local transition with `require`s; nothing asserts the cross-storage
relationship as a postcondition, and the trusted validator set / upgradeable proxy can write the
counters and state root directly — bypassing those local guards.

## Quarantined checks

- **Batch & priority ordering** (`assertBatchOrdering`) — `executed <= verified <= committed` for
  both batches and priority requests, and the open queue covers every committed-but-unexecuted
  request. You cannot execute (pay out) funds against state that was never proven.
- **Finality non-decrease** (`assertFinalityNonDecreasing`) — executed counters never roll
  back. Verified-but-unexecuted batches may be rolled back while remaining above the executed tip.
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
- `test/LighterBridgeAssertion.t.sol` — verifies that the wrapper registers no triggers;
  the retained `retired*` behavior functions are not executed tests.
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
- The current outflow tests exercise the pure `_breakerTrips` decision and constructor guards.
  They do not arm the rolling-window trigger or verify its executor integration. Validate that
  path separately before adoption; this repository does not establish production validation.
- The bridge suite only verifies quarantine. The retained state-machine and desert-mode behavior
  functions are named `retired*` and are not run by `pcl test`.
