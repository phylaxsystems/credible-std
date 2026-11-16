# Safe Protections

This package contains Safe-native protections. They cover different surfaces and run in different places:

- `SafeConfigLockAssertion` (Credible Layer assertion) checks the Safe configuration envelope after a transaction.
- `SafeTxShapeAssertion` (Credible Layer assertion) checks the direct actions a Safe is about to execute through owner or module entrypoints.
- `CredibleSafeGuard` (Safe transaction guard) allows owner/multisig Safe transactions only while the current block is credible, and fails open when the credible builder set is offline. It gates the owner-path `execTransaction` only; module executions bypass transaction guards (see [Scope](#scope)).

The two `*Assertion` contracts run inside the PhEvm. `CredibleSafeGuard` is a plain on-chain Gnosis Safe transaction guard installed on the Safe via `setGuard`.

## Credible Safe Guard (deprecated)

**Do not deploy or install this legacy copy.** The canonical implementation is
[`credible-registry/src/CredibleSafeGuard.sol`](https://github.com/phylaxsystems/credible-registry/blob/main/src/CredibleSafeGuard.sol).
This copy uses `isCredibleBlock(uint256)` rather than the current registry's `isCredibleBlock()`.
Against that registry, the failed selector probe makes every owner transaction fail open:
Safe interface compatibility does not imply credibility enforcement.

The source remains for legacy consumers and tests; the Safe assertion contracts below are
not deprecated or changed. Use the canonical [operations guide](https://github.com/phylaxsystems/credible-registry/blob/main/docs/SAFE_GUARD.md)
for deployment and onboarding. The local deployment/install entrypoints are disabled;
see the [legacy operations guide](../../../examples/safe-guard/README.md) for migration and removal.
The following compatibility and behavior sections describe the retained guard with a
compatible **legacy** registry, not the current registry.

### Safe compatibility

The integration suite runs against every guard-capable Safe contract release from 1.3.0 through
1.5.0:

| Safe release | Pinned revision | Singleton / proxy factory | Guard installation validation |
| --- | --- | --- | --- |
| 1.3.0 | `186a21a` | `GnosisSafe` / `GnosisSafeProxyFactory` | Transaction guards supported; no ERC-165 check |
| 1.4.0 | `e870f51` | `Safe` / `SafeProxyFactory` | `GS300` ERC-165 interface check |
| 1.4.1 | `21dc824` (`v1.4.1-3`) | `Safe` / `SafeProxyFactory` | `GS300` ERC-165 interface check |
| 1.5.0 | `dc437e8` | `Safe` / `SafeProxyFactory` | `GS300` ERC-165 interface check |

Safe 1.2.0 is not included because it does not implement transaction guards. The 1.4.1
dependency uses the `v1.4.1-3` source release, whose singleton reports contract version `1.4.1`.
The matrix follows the
[official Safe contract releases](https://github.com/safe-global/safe-smart-account/releases).

Safe 1.3.0 supports installing and running a transaction guard, but its `setGuard` implementation
accepts the address without validating ERC-165 support. Safe 1.4.0 and later reject a nonzero guard
unless it advertises the transaction-guard interface, reverting with `GS300`.
`CredibleSafeGuard` implements that interface and installs successfully on all four versions.

The shared lifecycle suite covers:

- Guard installation through an owner-signed `execTransaction` → `setGuard`, including the real
  `GS300` check on Safe 1.4.0 and later.
- Signed transactions executing in credible blocks and reverting with `NonCredibleBlock` in
  non-credible blocks while the builder set is live.
- Regular transactions and guard removal remaining blocked at exactly `failOpenBlockThreshold`,
  without changing the guard slot or consuming the Safe nonce.
- Guard removal succeeding at `failOpenBlockThreshold + 1`, and before expiry in a credible block.
- Fail-open after builder silence and when registry responses revert or are malformed, including
  recovery removal of the guard.
- An end-to-end builder stall-then-recover sequence.

The expiry comparison is strict: fail-open activates only when the gap from the latest credible
block is greater than `failOpenBlockThreshold`. Expiry is only needed for a healthy,
non-credible block; a credible block or an unavailable/malformed registry permits earlier
recovery, preserving the guard's existing policy.

The compatibility and operational tests are under
[`test/protection/safe/integration`](../../../test/protection/safe/integration) and use the
dedicated `safe-guard` Foundry profile because the pinned Safe contracts require the legacy
compiler pipeline (`optimizer = true`, no `via_ir`).

### What It Checks

On every Safe transaction the guard reads the Credible Registry and decides:

1. If a required registry read reverts, exceeds its gas budget, or returns malformed data, the registry is treated as unavailable, so the guard fails open and allows the transaction. This prevents a broken registry from locking the Safe.
2. If the current block is credible, the transaction is allowed.
3. Otherwise, if the most recent credible block lags the current block by more than `failOpenBlockThreshold` blocks, the credible builder set is treated as offline, so the guard fails open and allows the transaction. This keeps a stalled builder set from locking the Safe.
4. Otherwise the builder set is live and the current block is not credible, so the transaction reverts with `NonCredibleBlock`.

Registry probes are limited to 50,000 gas and copy exactly one 32-byte return word. A non-canonical boolean, short or oversized response, codeless registry address, or failed call activates fail-open instead of bubbling a failure through the Safe guard hook. This also preserves the owner path for replacing or removing the guard if the registry breaks.

### Config Options

Both values are immutable constructor arguments:

- `credibleRegistry`: address of the on-chain Credible Registry to query (`ICredibleRegistry`). Configurable per deployment; re-pointing means deploying a new guard and calling `setGuard` again.
- `failOpenBlockThreshold`: number of blocks of builder silence tolerated before failing open.

#### Choosing the fail-open threshold

The target is to fail open after roughly 15 minutes with no credible blocks. The Credible Registry records credibility by block number and does not expose timestamps, so the window is expressed as the number of blocks the builder set produces in about 15 minutes on the target chain:

| Block time | ~15 minutes |
| ---------- | ----------- |
| ~12s (Ethereum mainnet) | 75 blocks |
| ~2s (typical L2) | 450 blocks |
| ~1s | 900 blocks |

### Material Effect

- While the credible builder set is live, a Safe transaction cannot land in a non-credible block, such as one built by a builder that does not enforce assertions.
- If the credible builder set goes offline for longer than the configured window, or the registry becomes unreadable, the Safe keeps working.
- The guard gates only on block credibility and does not inspect the transaction target, value, calldata, or signatures. Pair it with `SafeConfigLockAssertion`, `SafeTxShapeAssertion`, or other assertions to constrain what the Safe may do within a credible block.

### Scope

`CredibleSafeGuard` is a Safe *transaction* guard, so it gates only the owner/multisig `execTransaction` path. Module executions (`execTransactionFromModule` / `execTransactionFromModuleReturnData`) bypass transaction guards entirely, so an enabled module can still execute while the current block is not credible. To gate module executions, install a separate Safe module guard (the v1.5.0 `checkModuleTransaction` hook) or protect that path with a Credible Layer assertion such as `SafeTxShapeAssertion`.

## Safe Tx Shape Assertion

`SafeTxShapeAssertion` blocks protected Safe executions whose direct action shape is outside policy, even when the Safe signers or a module authorize the transaction.

It watches:

- `execTransaction`
- `execTransactionFromModule`
- `execTransactionFromModuleReturnData`

The pack exposes one assertion function per enforced policy: `assertSafeModulePolicy`, `assertSafeDelegateCallPolicy`, `assertSafeTargetSelectorPolicy`, `assertSafeBatchPolicy`, and `assertSafeApprovalPolicy`.

Every watched execution is normalized into one or more actions. A normal owner or module transaction is one action. An approved `MultiSend` or `MultiSendCallOnly` transaction is expanded into its packed inner actions, and every inner action is checked with the same rules.

### What It Protects

- Unknown contract targets are blocked.
- Known targets must use an explicitly allowed selector unless the target is configured with the advanced `allowAnySelector` escape hatch.
- Empty calldata (zero bytes) is blocked unless the target sets `allowEmptyCalldata`.
- Sub-selector calldata (one to three bytes, routed to the fallback) is blocked unless the target sets `allowFallbackCalldata`.
- Native value attached to a selector is blocked unless that selector or target allows nonzero value.
- Owner transactions with nonzero signed `gasPrice` are blocked because Safe's refund payment has a separate token and receiver that this action policy does not model.
- Direct Safe `DELEGATECALL` and module `DELEGATECALL` are blocked except configured batch executors and the owner-signing exception below.
- A configured batch executor such as Safe `MultiSend` remains subject to its inner-action policy.
- Configured CALL-based batch executors such as `MultiSendCallOnly` are expanded as well.
- Batch payloads are parsed strictly using Safe's packed format: operation byte, target address, value, data length, and data bytes.
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

Owner signing policy:

- The final constructor argument, `ownerSigningLibraries_`, lists trusted signing-library addresses. Pass an empty array to retain the previous policy with no signing exception. Existing constructor encodings must append this array.
- Only a direct owner-authorized `execTransaction` delegatecall to a listed library's `signMessage(bytes)` function is exempted. Calldata must be canonical ABI encoding, and the declared value must be zero. Safe authenticates the owners; the exception does not use `tx.origin` or the outer transaction sender as evidence of authorization.
- Neither module entrypoint receives the exception, including when the module is otherwise allowlisted. Inner delegatecalls remain blocked: adding a signing library does not implicitly approve MultiSend or batched signing.
- Entries must be reviewed, immutable Safe signing libraries for the deployment's Safe version and chain, not upgradeable proxies or arbitrary delegatecall routers. The assertion trusts the configured code; it does not authenticate an address merely because it implements the signing selector. The on-chain guard must allow the same library and operation.

For the supported owner-only deployment, set `moduleExecutionEnabled=false`, leave `allowedModules_` and `batchExecutorPolicies_` empty, and configure the signing library in both the guard and this assertion. Generic batch/module options are not additional owner-only exceptions. Protect the Safe's singleton, owners, guards and handler separately; this execution policy assumes those authentication and validation components remain trusted.

This preserves both ordinary owner signatures and owner-approved `signedMessages` entries, including later ERC-1271 checks with empty signatures. No application-domain restriction is added, and existing stored approvals are not revoked. Signature validation itself does not invoke the transaction guard. The configuration lock alone still permits stored approvals: the execution policy rejects unauthorized signing and arbitrary delegatecall writers, including precomputed mapping-slot writes, rather than relying on heuristic mapping-key discovery.

The signing regression suite covers Safe 1.3.0, 1.4.0, 1.4.1 and 1.5.0:

```sh
RUST_MIN_STACK=16777216 FOUNDRY_PROFILE=ci pcl test --match-path 'test/protection/safe/SafeSign*.t.sol'
```

Keep the artifact tests in that filter so all version-specific binaries are available. CI's PCL 1.5.1 and PCL 1.6.0 both pass the suite. Real-proxy controls reproduce the config-lock gap and validate ordinary signatures and stored approvals against the upstream handlers with the configuration lock installed. These assertion tests do not depend on the library's guard implementation; combined guard/signing coverage belongs with the canonical guard in its consuming repository. Function-trigger tests use upstream singleton runtime over initialized Safe storage: PCL's `cl.assertion` requires exactly one invocation, while a proxy execution produces two. These checks are not a claim of full proxy/function-trigger integration coverage. Rejected-assertion cases each use a separate test because PCL ends the test frame on rejection.

Approval policy:

- token address;
- spender or operator address;
- approval kind;
- numeric cap for ERC-20 approval-style calls;
- explicit unlimited-approval permission.

Approval resets and revocations are allowed by default when the token is configured for that approval kind: ERC-20 `approve(spender, 0)`, ERC-721 `approve(address(0), tokenId)`, and `setApprovalForAll(operator, false)` reduce approval risk. Risk-increasing approvals to untrusted spenders/operators, ERC-20 unlimited approvals without explicit permission, and ERC-20 amounts above cap are blocked.

For ERC-20 `approve(spender, amount)` the cap binds `amount` directly. For ERC-20 `increaseAllowance(spender, addedValue)` it binds the allowance before the Safe entrypoint plus every positive increase for that token/spender in the batch. Spending and `approve(spender, 0)` do not replenish this conservative bound. For example, with cap 100, `increase 60; spend 60; increase 60` is rejected even though outstanding allowance never exceeds 60. This is not a general spending budget: repeated capped `approve` and spend calls are still allowed.

Positive `approve` and positive `increaseAllowance` cannot be mixed for the same token/spender in one batch, in either order. Different token/spender pairs remain independent. Zero approvals and zero increases do not count as mixed methods; a zero approval never clears accumulated increases. Standalone revocation is allowed even if the starting allowance exceeds the cap. Resetting an excessive allowance and increasing again requires separate Safe entrypoints.

Addition saturates at `uint256.max`. That sentinel always requires `allowUnlimited`, including when the numeric cap is also `uint256.max`. When enabled, the sentinel is allowed independently of the cap; finite bounds still obey the numeric cap. The bound is scoped to one Safe entrypoint, not a transaction-wide or time-window spending limit, and assumes the configured token implements the approval methods with ERC-20 semantics.

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

- The singleton slot stays equal to its pre-transaction value, including every intermediate change.
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

Module-set checks paginate Safe modules in pages of 256. Very large module sets may exceed the assertion gas limit while reading and hashing the full set; keep protected Safes below that practical cap or split module-heavy operational surfaces behind a smaller approved module set.

## Material Effect

- A transaction cannot reduce the Safe below the configured threshold or owner count.
- A transaction cannot quietly swap, add, or remove owners unless the resulting owner set is pre-approved.
- A transaction cannot enable an unexpected module, or any module at all when modules are disabled by policy.
- A transaction cannot change the transaction guard, module guard, or fallback handler away from the configured addresses.
- The check runs at transaction end and inspects the final configuration plus every intermediate singleton-slot value, regardless of the function path used to get there.

This does not decide who should be an owner, which modules are safe, or what guard logic is correct. Those choices are encoded by the hashes and expected addresses passed when the assertion is deployed.

## Singleton protection

The proxy's raw slot 0 must equal its pre-transaction value throughout execution.
The assertion compares both the post-state and every value returned by
`ph.getStateChanges(safe, bytes32(0))` against that starting value, using all 32 bytes.
Temporary replacements are rejected even if restored before transaction end;
writing the same value is allowed. The check does not trust an implementation-provided
`masterCopy()` view. No expected implementation or allowlist is configured, and the
existing constructor encoding is unchanged.

**No upgrade is allowed while this assertion is active**, even to another reviewed
Safe release or when authorized by the owners. For planned maintenance, the
assertion-policy manager must deactivate the lock and confirm deactivation is
effective before the Safe owners execute the upgrade. After verifying the new
implementation and configuration, reactivate the same assertion. Rollback uses
the same deactivate, migrate, and reactivate procedure. The assertion prevents
changes within protected transactions; it does not certify the implementation
already installed when protection starts, including changes made during maintenance.

`SafeTxShapeAssertion` separately blocks migration delegatecalls. Its blocking
policy must also be deliberately disabled or adjusted during authorized maintenance,
then restored. No general upgrade exception or module authority is added. The
on-chain Credible Safe Guard need not be removed. During deactivation, the disabled
assertions provide no protection; keep that interval controlled and short.

The installed implementation still needs trusted configuration getters and the supported
Safe storage layout. Tests cover Safe 1.3.0, 1.4.0, 1.4.1, and 1.5.0. Owner-set and
threshold behavior is unchanged: approved owner sets and minimum thresholds are
policies, not an unconditional freeze on all owner or threshold changes.
