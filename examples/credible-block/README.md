# Credible Block guard — upgrade tests

Integration scripts that exercise [`CredibleBlockGuard`](../../src/protection/credible_block/CredibleBlockGuard.sol)'s
`onlyCredibleBlock` modifier against a **live anvil node**, so we can validate credible-layer
contract upgrades end to end.

The forge unit tests in
[`test/protection/credible_block/`](../../test/protection/credible_block/CredibleBlockGuard.t.sol)
fake block state with `vm.roll` / `vm.prank`. That covers the pure decision logic, but it cannot
reproduce the one thing that only exists on a real chain: a builder's *credible block marker*
transaction and a *guarded* transaction landing in the **same block** (a bundle). These scripts seed
a real node and drive mining manually so we can test exactly that.

## Contents

| File | Role |
| ---- | ---- |
| [`src/CredibleRegistry.sol`](./src/CredibleRegistry.sol) | Minimal deployable registry: a single immutable builder (set at construction) can mark the current block credible; implements [`ICredibleRegistry`](../../src/protection/credible_block/ICredibleRegistry.sol). The production registry ([`phylaxsystems/credible-registry`](../../../credible-registry)) additionally has a timelocked admin, a builder whitelist, and timestamp slot-binding — none needed to exercise the guard. |
| [`src/GuardedCounter.sol`](./src/GuardedCounter.sol) | A concrete `CredibleBlockGuard` standing in for an upgraded credible-layer contract; its `bump()` entrypoint is `onlyCredibleBlock`. |
| [`script/test-credible-upgrades.sh`](./script/test-credible-upgrades.sh) | Orchestrator that boots anvil, deploys, and runs the three cases. |

## Cases

| Case | Scenario | Expectation |
| ---- | -------- | ----------- |
| **1. Credible block** | Bundle `[markCurrentBlockCredible, bump]` into one block via manual mining | Both txs succeed; counter increments |
| **2. Non-credible block** | Send only `bump()` with no marker | Reverts with `NonCredibleBlock()`; counter unchanged |
| **3. Fail-open** | Builder stops marking for `> failOpenBlockThreshold` blocks | Still reverts at the boundary (gap == threshold); passes once gap > threshold |

## How the bundle is simulated

Anvil auto-mines each tx into its own block by default, which would put the marker and the guarded
call in different blocks. The script turns automine **off** (`evm_setAutomine false`), submits both
txs with `cast send --async` (returns immediately without waiting for a receipt), then seals exactly
one block with `evm_mine`. Both queued txs land together; `--order fifo` guarantees the marker
executes first, so the guarded call sees the block already marked credible.

## Running

From the repo root:

```shell
./examples/credible-block/script/test-credible-upgrades.sh
```

Requires `anvil`, `cast`, `forge`, and `jq` on `PATH`. Exits non-zero if any check fails. Env
overrides: `RPC_PORT` (default `8545`), `FAIL_OPEN_THRESHOLD` (default `10`, kept small so the
fail-open case runs quickly).

The script uses the `credible-block` foundry profile (see `foundry.toml`); it sets
`FOUNDRY_PROFILE=credible-block` itself.

> On macOS, `cast`/`forge` read system proxy configuration at startup, which the Claude Code Bash
> sandbox blocks (the process aborts with a NULL-object panic). Run this script with the sandbox
> disabled.
