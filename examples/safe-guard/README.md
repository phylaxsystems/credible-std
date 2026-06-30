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
- An end-to-end builder stall-then-recover sequence.

## Run

```sh
FOUNDRY_PROFILE=safe-guard forge test
```

The Safe contracts come from the `safe-smart-account` submodule under `lib/`, so initialize submodules first (`git submodule update --init --recursive`).
