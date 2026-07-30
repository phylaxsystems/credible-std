# Credible-block live upgrade validation

This directory contains a live-Anvil integration runner for
[`CredibleBlockGuard`](../../src/protection/credible_block/CredibleBlockGuard.sol). It proves the
marker transaction and guarded user transaction can execute in the same manually mined block, and
also exercises rejection and strict fail-open behavior.

`GuardedCounter` is the default runnable fixture. A passing fixture run proves the harness and base
guard work; it does **not** validate a protocol upgrade. Use target mode to validate the actual
upgraded contract.

## What is tested

| Case | Expected transaction result | Required state proof |
| --- | --- | --- |
| Marker then guarded call, queued and mined together | Both succeed in the same block | Target state changes from `--state-before` to `--state-after` |
| Guarded call alone while the builder window is live | Reverts with `--guard-error` | Target state remains `--state-before` |
| Builder inactivity | Reverts at `gap == threshold`; succeeds at `gap > threshold` | State is unchanged at the boundary and changes after fail-open |

The runner starts Anvil with FIFO transaction ordering, disables automining, submits both same-block
transactions with `cast send --async`, and calls `evm_mine` once. Do not replace this with two
automined sends: they would be in different blocks and would not test credible-block bundling.

## Fixture run

From the repository root:

```shell
./examples/credible-block/script/test-credible-upgrades.sh
```

This deploys the minimal [`CredibleRegistry`](./src/CredibleRegistry.sol) and
[`GuardedCounter`](./src/GuardedCounter.sol), calls `bump()`, and reads `count()`. The expected output
identifies the run as `GuardedCounter fixture coverage`, reports three case sections, and finishes
with `Summary: 14 passed, 0 failed`.

## Real upgraded-contract run

The target and registry must exist on the fresh Anvil instance started by the runner. Usually this
means supplying deployment/upgrade commands:

```shell
./examples/credible-block/script/test-credible-upgrades.sh \
  --registry-deploy-command \
    'forge script script/DeployRegistry.s.sol --rpc-url "$RPC_URL" --broadcast; echo 0xREGISTRY' \
  --target-deploy-command \
    'forge script script/UpgradeVault.s.sol --rpc-url "$RPC_URL" --broadcast; echo 0xPROXY' \
  --guarded-call 'deposit(uint256) 1000000' \
  --state-read-call 'totalAssets()(uint256)' \
  --state-before 0 \
  --state-after 1000000 \
  --expected-threshold 75 \
  --marker-private-key 0xMARKER_PRIVATE_KEY \
  --guarded-private-key 0xUSER_PRIVATE_KEY
```

Each deployment command must print its resulting address as the final stdout line. Commands receive
these exported variables: `RPC_URL`, `REPO_ROOT`, `ADMIN_KEY`, `MARKER_KEY`, `GUARDED_KEY`,
`MARKER_ADDRESS`, `GUARDED_ADDRESS`, `REGISTRY_ADDRESS` (for the target command), and
`EXPECTED_THRESHOLD`. The commands are passed to `bash -c`; only run trusted command text.

For contracts already created by a setup command, use `--registry-address` and `--target-address`.
Because every run starts a fresh chain, addresses from another node are not usable.

The full input surface is:

```text
--target-address ADDRESS | --target-deploy-command COMMAND
--registry-address ADDRESS | --registry-deploy-command COMMAND
--guarded-call "SIGNATURE [ARGS...]"
--marker-call "SIGNATURE [ARGS...]"                 # default markCurrentBlockCredible()
--state-read-call "SIGNATURE [ARGS...]"
--state-before VALUE
--state-after VALUE
--expected-threshold BLOCKS
--marker-private-key KEY
--guarded-private-key KEY
--admin-private-key KEY
--guard-error SIGNATURE                             # default NonCredibleBlock()
--rpc-port PORT
--gas-limit GAS
```

The default configuration check calls `credibleRegistry()(address)` and
`failOpenBlockThreshold()(uint256)` on the target. Override their signatures with
`--registry-read-call` and `--threshold-read-call`. If the upgrade exposes no suitable getters,
provide a contract-specific adapter/assertion:

```shell
--config-assert-command \
  'cast call --rpc-url "$RPC_URL" "$TARGET_ADDRESS" "guardConfigHash()(bytes32)" |
   grep -qi "$(cast keccak "$(cast abi-encode "f(address,uint256)" \
     "$REGISTRY_ADDRESS" "$EXPECTED_THRESHOLD")")"'
```

The assertion must exit zero only after proving that `TARGET_ADDRESS` uses exactly
`REGISTRY_ADDRESS` and `EXPECTED_THRESHOLD`. A deployment script may instead assert the immutable,
storage slot, or emitted upgrade/configuration event and expose that assertion through this hook.
The runner fails before behavioral cases when the assertion fails.

Use `--validate-only` to check arguments without starting Anvil. Argument parsing regression tests
run with:

```shell
./examples/credible-block/test/test-script-arguments.sh
```

## Requirements and limitations

- `anvil`, `cast`, `forge`, and `jq` must be on `PATH`.
- The selected RPC port must be unused; the runner refuses to adopt an existing node.
- The marker account must be authorized by the supplied registry configuration.
- The guarded account must have all target-specific balances, approvals, roles, and prerequisites.
  Deployment commands are responsible for arranging them.
- `--state-read-call` must return one stable, directly comparable `cast call` value. For complex
  effects, deploy a read-only adapter that returns a digest or scalar assertion value.
- Each success case starts from the same post-deployment snapshot, so `--state-before` and
  `--state-after` describe one guarded call.
- The runner validates guard wiring and behavior, not the correctness or completeness of the
  upgrade process itself.
- The `credible-block` Foundry profile is selected automatically.
- On macOS, Foundry may abort while reading system proxy settings inside a restricted sandbox. Run
  the live integration outside that sandbox; `--validate-only` and the argument tests do not start
  Foundry and can remain sandboxed.
