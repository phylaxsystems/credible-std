# Credible Safe Guard integration

Real end-to-end tests for `src/protection/safe/CredibleSafeGuard.sol`, run against an actual Gnosis Safe (v1.4.1).

The guard contract and its unit tests live in the root project:

- `src/protection/safe/CredibleSafeGuard.sol`
- `src/protection/safe/ICredibleRegistry.sol`
- `test/protection/safe/CredibleSafeGuard.t.sol` (unit tests)

These integration tests live under their own profile because the Safe contracts compile with the legacy pipeline (`optimizer = true`, no `via_ir`), while the root profiles use `via_ir`.

## What it covers

- Installing the guard on a real Safe via a signed `execTransaction` → `setGuard`, which exercises Safe's real `GS300` ERC-165 check against the guard.
- A signed Safe transaction executing in a credible block.
- A signed Safe transaction reverting with `NonCredibleBlock` in a non-credible block while the builder set is live.
- The fail-open path: a signed Safe transaction executing once the builder set has been silent past the configured window.
- Registry-unavailability fail-open paths, including reverted and malformed registry responses.
- An end-to-end builder stall-then-recover sequence.

## Deploy the guard

The deployment script reads the registry, fail-open threshold, and initial protocol manager from the environment. Foundry handles the deployer wallet; the script does not read a private key.

```sh
FOUNDRY_PROFILE=safe-guard \
CREDIBLE_REGISTRY=0x... \
FAIL_OPEN_BLOCK_THRESHOLD=75 \
INITIAL_PROTOCOL_MANAGER=0x... \
forge script examples/safe-guard/script/DeployCredibleSafeGuard.s.sol \
  --rpc-url "$RPC_URL" \
  --account <foundry-keystore-account> \
  --broadcast
```

Foundry hardware-wallet flags such as `--ledger` or `--trezor` can be used instead of `--account`.

## Create a Safe{Wallet} installation transaction

`GenerateSafeGuardBatch.s.sol` creates an official Safe Transaction Builder JSON batch. It does not sign, broadcast, call `execTransaction`, or submit anything to the Safe Transaction Service.

```sh
FOUNDRY_PROFILE=safe-guard \
SAFE_ADDRESS=0x... \
SAFE_GUARD_ACTION=install \
CREDIBLE_SAFE_GUARD=0x... \
forge script examples/safe-guard/script/GenerateSafeGuardBatch.s.sol \
  --rpc-url "$RPC_URL"
```

The output is written to:

```text
safe-guard-output/install.json
```

To install the guard:

1. Open the target Safe in Safe{Wallet} on the same chain used to generate the file.
2. Open **Apps → Transaction Builder**.
3. Import `safe-guard-output/install.json`.
4. Verify that the transaction target is the Safe itself, the value is zero, and the decoded call is `setGuard(<deployed guard>)`.
5. Create the Safe transaction and complete the Safe's normal owner confirmation and execution flow.

Safe's `setGuard` function is self-authorized. A Safe owner cannot call it directly; the call must execute through an owner-authorized Safe transaction targeting the Safe itself. The generated batch provides exactly that inner transaction and includes a Transaction Builder checksum so the UI can detect modification.

## Create a removal transaction

Removal uses the same Safe self-call with the guard set to the zero address:

```sh
FOUNDRY_PROFILE=safe-guard \
SAFE_ADDRESS=0x... \
SAFE_GUARD_ACTION=remove \
forge script examples/safe-guard/script/GenerateSafeGuardBatch.s.sol \
  --rpc-url "$RPC_URL"
```

Import `safe-guard-output/remove.json` into Transaction Builder and verify that it displays `setGuard(0x0000000000000000000000000000000000000000)` before submitting it.

If a guard is already installed, that current guard checks a replacement or removal transaction before Safe executes it. `CredibleSafeGuard` therefore requires the transaction to land in a credible block while the builder set is live. Its fail-open behavior still permits recovery if the builder set is stale or a required registry read is unavailable or malformed.

Importing a batch does not automatically publish it to the Safe transaction queue. The owner creates the proposal from Transaction Builder after reviewing the imported action. Automatically inserting a transaction into the queue would require a separate Safe owner signature and Safe Transaction Service integration.

Generated files under `safe-guard-output/` are ignored by Git. Always verify the chain, Safe address, action, guard address, and decoded call in Safe{Wallet} before signing.

## Run tests

```sh
FOUNDRY_PROFILE=safe-guard forge test
```

The Safe contracts come from the `safe-smart-account` submodule under `lib/`, so initialize submodules first (`git submodule update --init --recursive`).
