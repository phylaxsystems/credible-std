# Safe Assertions

This package contains Safe-native assertion packs. They are intentionally separate because they protect different surfaces:

- `SafeConfigLockAssertion` checks the Safe configuration envelope after a transaction.
- `SafeTxShapeAssertion` checks the direct actions a Safe is about to execute through owner or module entrypoints.

## Safe Tx Shape Assertion

`SafeTxShapeAssertion` blocks protected Safe executions whose direct action shape is outside policy, even when the Safe signers or a module authorize the transaction.

It watches:

- `execTransaction`
- `execTransactionFromModule`
- `execTransactionFromModuleReturnData`

The pack exposes one assertion function per enforced policy: `assertSafeModulePolicy`, `assertSafeDelegateCallPolicy`, `assertSafeTargetSelectorPolicy`, `assertSafeBatchPolicy`, and `assertSafeApprovalPolicy`.

Every watched execution is normalized into one or more actions. A normal owner or module transaction is one action. An approved `MultiSend` transaction is expanded into its packed inner actions, and every inner action is checked with the same rules.

### What It Protects

- Unknown contract targets are blocked.
- Known targets must use an explicitly allowed selector unless the target is configured with the advanced `allowAnySelector` escape hatch.
- Empty calldata (zero bytes) is blocked unless the target sets `allowEmptyCalldata`.
- Sub-selector calldata (one to three bytes, routed to the fallback) is blocked unless the target sets `allowFallbackCalldata`.
- Native value attached to a selector is blocked unless that selector or target allows nonzero value.
- Direct Safe `DELEGATECALL` and module `DELEGATECALL` are blocked.
- The only delegatecall exception is a configured batch executor such as Safe `MultiSend`.
- `MultiSend` payloads are parsed strictly using Safe's packed format: operation byte, target address, value, data length, and data bytes.
- Malformed, truncated, overlong, nested, or delegatecall-containing batches are blocked.
- ERC-20 `approve`, ERC-20 `increaseAllowance`, ERC-721 `approve`, ERC-721 `setApprovalForAll`, and ERC-1155 `setApprovalForAll` receive a separate approval-policy check.

### What It Does Not Protect

This is not an outflow circuit breaker and not a Safe configuration lock. It does not measure final asset movement, price impact, solvency, owner changes, threshold changes, guard changes, or module set changes.

This assertion validates the shape of actions the Safe directly executes. It does not fully model arbitrary downstream behavior inside trusted routers. If a trusted router internally moves funds or calls unknown contracts, that must be handled by separate effect-based assertions or by making the router-specific policy narrower.

### How It Differs From SafeConfigLockAssertion

`SafeConfigLockAssertion` runs at transaction end and checks the Safe's final owner, module, threshold, guard, module guard, and fallback-handler state.

`SafeTxShapeAssertion` runs on each Safe execution call and checks the requested action tuple: target, value, calldata, operation, module caller, batch contents, and approval spender/operator. It can block a dangerous action even when the transaction would leave the Safe configuration unchanged.

### Policy Model

The MVP uses constructor-driven policy arrays.

Known target policy:

- `target`: contract address the Safe may call.
- `allowAnySelector`: permits any selector for that target. This should be rare.
- `allowEmptyCalldata`: permits empty calldata calls.
- `allowFallbackCalldata`: permits calldata shorter than four bytes.
- `allowNonzeroValue`: permits native value for target-level empty, fallback, or any-selector calls.

Selector policy:

- exact `(target, selector)` pairs;
- per-selector native value permission.

Batch executor policy:

- approved executor address;
- approved batch selector, normally `multiSend(bytes)`;
- whether top-level delegatecall to that executor is allowed;
- maximum inner action count;
- nested batching flag, reserved for future support and rejected in this MVP.

Module policy:

- module execution can be disabled entirely;
- when enabled, the module caller must be allowlisted;
- allowlisted modules still must pass the same target, selector, delegatecall, batch, and approval checks.

Approval policy:

- token address;
- spender or operator address;
- approval kind;
- numeric cap for ERC-20 approval-style calls;
- explicit unlimited-approval permission.

Approval resets and revocations are allowed by default when the token is configured for that approval kind: ERC-20 `approve(spender, 0)`, ERC-721 `approve(address(0), tokenId)`, and `setApprovalForAll(operator, false)` reduce approval risk. Risk-increasing approvals to untrusted spenders/operators, ERC-20 unlimited approvals without explicit permission, and ERC-20 amounts above cap are blocked.

For ERC-20 `approve(spender, amount)` the cap binds `amount` directly. For ERC-20 `increaseAllowance(spender, addedValue)` the cap binds the post-state `allowance(safe, spender)` so two consecutive `increaseAllowance` calls inside a `MultiSend` cannot stack above the cap.

### Material Effect

- A compromised UI cannot redirect signers to an arbitrary contract with arbitrary calldata.
- A broad target allowlist is not enough to approve token approvals; spender/operator and amount policy still applies.
- A module cannot bypass owner-path policy unless module execution is enabled and the module caller is allowlisted.
- Safe `MultiSend` cannot hide an unknown target, unknown selector, approval grant, nested batch, malformed packed entry, or inner delegatecall.

Conceptual examples:

- Treasury Safe: allow only known token `transfer` selectors, known vesting contract claim selectors, and zero approval resets.
- Operations Safe: allow an audited bridge adapter selector with no native value and a capped ERC-20 approval only to that adapter.
- NFT custody Safe: allow marketplace listing functions but block `setApprovalForAll(true)` except to a time-bounded, trusted operator enforced by a separate deployment policy.

## Safe Config Lock Assertion

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
