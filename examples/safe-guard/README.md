# Legacy Credible Safe Guard operations (deprecated)

**Do not deploy or install `src/protection/safe/CredibleSafeGuard.sol` from credible-std.**
The canonical guard is [`credible-registry/src/CredibleSafeGuard.sol`](https://github.com/phylaxsystems/credible-registry/blob/main/src/CredibleSafeGuard.sol).
Use that repository's [deployment and onboarding guide](https://github.com/phylaxsystems/credible-registry/blob/main/docs/SAFE_GUARD.md).

This retained copy calls `isCredibleBlock(uint256)` while the current registry implements
`isCredibleBlock()`. The unsupported selector fails its probe, so it **fails open on every
owner transaction** against the current registry. It provides no credibility protection in
that configuration. The legacy deployment validator is not equivalent to the canonical
validator either: it uses unbounded reads and accepts future last-credible-block heights.

This deprecation does not remove the contract, change its runtime behavior, or deprecate
the assertion library. Existing pinned consumers keep their source/API compatibility.
It does not patch already deployed guards or historical tags and pins.

The guard contract, compatibility matrix, and tests live with the Safe protection package:

- `src/protection/safe/CredibleSafeGuard.sol`
- `src/protection/safe/ICredibleRegistry.sol`
- `src/protection/safe/README.md`
- `test/protection/safe/CredibleSafeGuard.t.sol`
- `test/protection/safe/integration/`

## Deployment and installation are disabled

`DeployCredibleSafeGuard.run()` always reverts before reading configuration or broadcasting.
`GenerateSafeGuardBatch.run()` rejects `SAFE_GUARD_ACTION=install` before writing a batch.
Both errors point to the corresponding script in credible-registry. The low-level `deploy`
and `buildInstallBatch` helpers remain for legacy source compatibility and historical tests,
but print deprecation warnings. They must not be used for new deployments or onboarding.

For an existing installation, inspect its registry address and ABI. The registry address is
immutable: updating this library cannot repair a deployed guard. Deploy a canonical guard
using credible-registry's tooling, configure its protocol manager and assertions, and use
that repository's installation batch to replace the legacy guard through an owner-authorized
Safe self-call to `setGuard(newGuard)`. Review the chain, Safe, new guard, and assertion
configuration before signing. A replacement is checked by the currently installed guard.
Do not assume a healthy legacy guard can be replaced or removed in a noncredible block.

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
FOUNDRY_PROFILE=safe-guard pcl test
```

For a focused compatibility-matrix run during development:

```sh
FOUNDRY_PROFILE=safe-guard forge test \
  --match-path test/protection/safe/integration/CredibleSafeGuardSafeIntegration.t.sol
```

The Safe contracts come from pinned `safe-smart-account` submodules under `lib/`, so initialize
submodules first (`git submodule update --init --recursive`).
