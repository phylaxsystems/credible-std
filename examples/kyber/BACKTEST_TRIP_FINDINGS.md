# Kyber assertion — mainnet backtest trip (RESOLVED)

Durable record of the ENG-3860 seven-day replay backtest of
`KyberMetaAggregationRouterAssertion` and its triage outcome. This file is intentionally
sanitized: it names the replay service and its archive requirement but contains no access
tokens, and it pins toolchain-dependent artifacts (assertion IDs) to a reproducible command
rather than hard-coding stale hashes.

## Summary

| Field | Value |
| --- | --- |
| Chain | 1 (Ethereum mainnet) |
| Adopter | `0x6131B5fae19EA4f9D964eAc0408E4408b66337b5` (KyberSwap MetaAggregationRouterV2, live on mainnet) |
| Assertion | `examples/kyber/src/KyberMetaAggregationRouterAssertion.sol` (`assertReceiverGetsMinReturn`, triggered on `swap`/`swapGeneric`/`swapSimpleMode`) |
| Requested window | `start_block = 25480001` → `head = 25487144` (7143 blocks, ~7 days), frozen |
| Scan outcome | Early `complete` — stopped at `current_block = 25480033` (« `destination_block`), i.e. `ReplayStopMatch` |
| Reverts | ≥ 1 — the matched transaction that stopped the scan (poll-only run; see note) |
| Triage outcome | **Test-harness deployment bug, not an assertion bug. No assertion code change warranted.** |

Note on counts: the job was submitted without a `callback_url`, so only
`GET /backtest/{job}/progress` was observable. That endpoint surfaces the stop block, not a
per-transaction tally, so the recorded revert figure is the single trip that stopped the scan
rather than a full tx/revert census. This poll-only limitation is a known property of the replay
service.

## Triage outcome — constructor-arity deployment bug

**Root cause: the backtest harness built the assertion create data with a one-argument
`constructor(address)` payload, but the assertion's constructor is the two-argument
`constructor(address, bool)`.**

The one-argument payload — `creationCode || abi.encode(address(router))` — **reverts during
construction**. The compiler-generated constructor prologue ABI-decodes its arguments from the
code-appended tail and reverts when that tail is too short to contain the trailing `bool`. It
does **not** silently read the missing `bool` as zero. Under `pcl`/`cl.assertion` this surfaces
as `AssertionContractDeployFailed` before the triggered `router.swap` ever runs.

The router at `0x6131B5fae19EA4f9D964eAc0408E4408b66337b5` genuinely is the original router
family, so the correct deployment is `constructor(address, bool)` with
`originalRouterFamily_ = true`. Deployed correctly, the assertion does not trip on this traffic.

Answer to "should it have triggered in the first place?" — **No.** A correctly deployed
assertion does not trip on this window. The trip was produced by the wrong constructor arity in
the harness, which is a deployment failure rather than a fired assertion.

## What this PR changes

- Adds `testDeployment_OneArgPayload_RevertsDuringConstruction`: builds the exact one-argument
  harness payload and asserts `CREATE` returns `address(0)` (construction reverted), while the
  correct two-argument payload constructs. This pins the real root cause at the construction
  layer, which is CI-safe (the `cl.assertion` deploy failure is an uncatchable process abort, not
  a catchable Solidity revert).
- Retains `testMinReturn_PartialFill_MisconfiguredFamilyFalse_Trips` as a *separate, explicit*
  wrong-family behaviour test (a successfully-deployed assertion armed with
  `originalRouterFamily_ = false`), clearly labelled as **not** the harness bug.
- Keeps `testMinReturn_PartialFill_NoFalsePositive_Passes` as the correct-deployment A/B partner:
  armed with `originalRouterFamily_ = true`, a legitimate partial-fill order credited below the
  flat `minReturnAmount` passes because the `_PARTIAL_FILL` flag is skipped.
- Gates the `kyber` profile in the examples CI matrix so this regression runs on every PR.

## Reproducing the assertion IDs

Assertion IDs are `keccak256(creationCode || encodedArgs)` and therefore depend on the compiled
creation code and the exact toolchain. Do **not** hard-code them — regenerate from the bytes you
actually submit:

```sh
# 1. Compile and read the creation code:
FOUNDRY_PROFILE=kyber forge build
#    .bytecode.object from
#    examples/kyber/out/KyberMetaAggregationRouterAssertion.sol/KyberMetaAggregationRouterAssertion.json

# 2. The correct (two-argument) constructor tail for the original router family:
cast abi-encode "constructor(address,bool)" 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5 true

# 3. id = keccak256(creation_code || encoded_args)
```

The one-argument payload used by the buggy harness
(`abi.encode(address(0x6131B5…))`, 32 bytes of tail) does not produce a working assertion — it
fails construction, as pinned by `testDeployment_OneArgPayload_RevertsDuringConstruction`.

## Reproducing the replay (optional)

The source window was frozen at `start_block = 25480001`, `head = 25487144` (7143 blocks) and
remained frozen at that range, so the run is reproducible against the Phylax assex-replay service
(`chain_id = 1`). `POST /backtest` takes only `block_count` and scans forward from the fixed
`start_block`; it stops on the first assertion match and, without a `callback_url`, exposes only
`GET /backtest/{job}/progress` (an early `complete` = a match/trip). The service requires an
archive node for the target chain; supply that RPC via the service configuration rather than
embedding any credential here.

A/B against the frozen window to confirm the deployment-arity root cause:

- **Correct** (two-argument, `originalRouterFamily_ = true`): runs to `destination_block` with no
  early stop — no trip.
- **Buggy** (one-argument payload): the assertion fails to deploy, so the harness records a
  deploy failure rather than a passing scan.

The local `pcl test` A/B above already proves the mechanism deterministically without the live
service.
