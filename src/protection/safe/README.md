# Safe Config Lock Assertion

`SafeConfigLockAssertion` keeps a Safe multisig inside an approved configuration envelope after every protected transaction.

It is meant for teams that know what their Safe configuration should look like and want Credible to block transactions that leave the Safe in a weaker or unexpected state.

## What It Checks

- The Safe threshold is at least `minThreshold`.
- The Safe owner count is at least `minOwners`.
- The full owner set matches one of `approvedOwnerSetHashes`.
- The full module set matches one of `approvedModuleSetHashes`.
- The transaction guard equals `expectedGuard`.
- The module guard equals `expectedModuleGuard`.
- The fallback handler equals `expectedFallbackHandler`.

## Config Options

- `minThreshold`: minimum number of owners required to approve normal Safe transactions.
- `minOwners`: minimum number of owners that must remain on the Safe.
- `approvedOwnerSetHashes`: hashes of owner sets the Safe is allowed to have.
- `approvedModuleSetHashes`: hashes of module sets the Safe is allowed to have.
- `expectedGuard`: required transaction guard address. Use `address(0)` to require no transaction guard.
- `expectedModuleGuard`: required module guard address. Use `address(0)` to require no module guard.
- `expectedFallbackHandler`: required fallback handler address. Use `address(0)` to require no fallback handler.

Owner and module set hashes are computed by sorting addresses ascending and hashing `abi.encode(sortedAddresses)`.

For modules, `bytes32(0)` in `approvedModuleSetHashes` means modules must be disabled. This is useful when the safest policy is that only owner-approved Safe transactions may execute.

## Material Effect

- A transaction cannot reduce the Safe below the configured threshold or owner count.
- A transaction cannot quietly swap, add, or remove owners unless the resulting owner set is pre-approved.
- A transaction cannot enable an unexpected module, or any module at all when modules are disabled by policy.
- A transaction cannot change the transaction guard, module guard, or fallback handler away from the configured addresses.
- The check runs at transaction end, so it cares about the final Safe configuration rather than the specific function path used to get there.

This does not decide who should be an owner, which modules are safe, or what guard logic is correct. Those choices are encoded by the hashes and expected addresses passed when the assertion is deployed.
