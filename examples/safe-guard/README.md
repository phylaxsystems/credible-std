# Credible Safe Guard operations

Deployment and Safe Transaction Builder tooling for
`src/protection/safe/CredibleSafeGuard.sol`.

The guard contract, compatibility matrix, and tests live with the Safe protection package:

- `src/protection/safe/CredibleSafeGuard.sol`
- `src/protection/safe/ICredibleRegistry.sol`
- `src/protection/safe/README.md`
- `test/protection/safe/CredibleSafeGuard.t.sol`
- `test/protection/safe/integration/`

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

Set optional `OWNER_SIGNING_LIBRARIES` to comma-separated reviewed immutable, non-proxy signing
library addresses. Unset or empty disables all delegatecalls. The guard constructor and `deploy`
helper take this list as a trailing `address[]`. The script prints each target and its pinned runtime
hash. Only direct owner-authorized `signMessage(bytes)` delegatecalls with zero declared value and
canonical ABI are admitted, subject to credibility/fail-open. Code hashes cannot detect proxy
upgrades or certify library behavior; review targets and dependencies. Configure the corresponding
assertion signing exception too (ENG-6173). No MultiSend, nested signing or module exception exists.

## Create a Safe{Wallet} installation transaction

`GenerateSafeGuardBatch.s.sol` creates an official Safe Transaction Builder JSON batch. It does not sign, broadcast, call `execTransaction`, or submit anything to the Safe Transaction Service.

This guard supports **owner-only Safes**, with only the configured owner-signing exception, on 1.3.0–1.5.0.
Before installation, review clean provenance as described in the protection package's
[scope](../../src/protection/safe/README.md#scope): no existing authorized modules (including
hidden mapping entries), no unsafe setup/history, and no self fallback handler. An empty module
list alone cannot establish this. The generator rejects listed modules and self fallback handlers
but cannot prove absence of orphans. Set the acknowledgement below only after that review,
and recheck intervening transactions before execution. It is not an on-chain admission proof.

```sh
FOUNDRY_PROFILE=safe-guard \
SAFE_ADDRESS=0x... \
SAFE_GUARD_ACTION=install \
SAFE_OWNER_ONLY_PROVENANCE_CONFIRMED=true \
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

Use a direct owner-authorized `CALL`, not delegatecall-based MultiSend. Removal does not require
the provenance acknowledgement or an empty module list. It ends the owner-only guarantee;
re-review the Safe before reinstalling. Separate assertions that lock the guard need their own
authorized recovery/deactivation route.

Importing a batch does not automatically publish it to the Safe transaction queue. The owner creates the proposal from Transaction Builder after reviewing the imported action. Automatically inserting a transaction into the queue would require a separate Safe owner signature and Safe Transaction Service integration.

Generated files under `safe-guard-output/` are ignored by Git. Always verify the chain, Safe address, action, guard address, and decoded call in Safe{Wallet} before signing.

## Run tests

```sh
FOUNDRY_PROFILE=safe-guard pcl test
```

For a focused compatibility-matrix run during development:

```sh
FOUNDRY_PROFILE=safe-guard forge test \
  --match-path test/protection/safe/integration/CredibleSafeGuardSafeIntegration.t.sol
```

The Safe contracts come from pinned `safe-smart-account` submodules under `lib/`, so initialize
submodules first (`git submodule update --init --recursive`).
