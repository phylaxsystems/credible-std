# Safe Assertions

This package contains Credible Layer assertions for Safe deployments. They run
inside the PhEvm.

## Safe Tx Shape Assertion

`SafeTxShapeAssertion` checks the direct actions a Safe is about to execute
through owner or module entrypoints. It watches `execTransaction`,
`execTransactionFromModule`, and `execTransactionFromModuleReturnData`.

The assertion can enforce policies for:

- allowed targets and selectors;
- native value, delegatecall, and fallback-calldata use;
- Safe `MultiSend` and `MultiSendCallOnly` batches;
- module callers; and
- ERC-20, ERC-721, and ERC-1155 approval grants.

It normalizes owner and module executions into actions, expands configured Safe
batch executors, and rejects malformed, nested, or delegatecall-containing
batches. It validates the action shape, not arbitrary downstream behavior in a
trusted router; pair it with effect-based assertions when that is required.

## Safe Config Lock Assertion

`SafeConfigLockAssertion` checks the Safe's final configuration after each
protected transaction. Its constructor policy can require a minimum threshold
and owner count, approved owner/module sets, and expected transaction guard,
module guard, and fallback-handler addresses.

`expectedGuard` may be `address(0)` when no transaction guard is allowed. Owner
and module set hashes are computed from ascending-sorted addresses using
`keccak256(abi.encode(sortedAddresses))`.

The final constructor argument, `approvedSingletons`, is a nonempty list of
reviewed Safe implementation addresses. The proxy's slot 0 must contain an
approved implementation before, throughout, and after the transaction, including
temporary replacements that are restored before transaction end. These are raw
storage checks, not calls to an implementation-provided `masterCopy()` view.
A one-address list freezes the implementation; listing an additional reviewed
implementation permits an upgrade to it through the deployment's existing
execution policy. This is not an authorization check on who initiates an upgrade.
Every listed implementation must have the supported Safe storage layout and
trusted configuration views. The tests cover Safe 1.3.0, 1.4.0, 1.4.1, and 1.5.0.
Existing constructor encodings must append this argument when adopting this version.

### Module authorization is not module enumeration

The configuration lock hashes the sentinel-linked module list. Safe authorizes
module execution using a separate mapping lookup: a nonzero entry can authorize
an address that is absent from that list. Therefore the configuration lock alone
does **not** freeze effective module authorization, even with an empty-list policy.
`SafeOrphanModule.t.sol` demonstrates creation via a precomputed storage slot and
successful hidden-module execution on all four supported Safe releases.

An explicit `SafeTxShapeAssertion.assertSafeModulePolicy` allowlist protects both
module entrypoints independently of enumeration. The delegatecall policy also
blocks the demonstrated arbitrary-storage writer, when that policy is installed.
These are separate, opt-in execution policies, not guarantees of the config lock.
Deployments must decide which modules and delegatecall executors they support;
an approved executor that can write arbitrary Safe storage remains trusted.
Mapping-key discovery is best-effort and cannot close this gap. This limitation
is not resolved by pagination changes or the singleton allowlist.

### Signed-message policy remains separate

The configuration lock does not freeze `signedMessages`. With the compatibility
fallback handler, an enabled module can delegatecall the signing library and
make a new message valid to ERC-1271 consumers without changing the checked
configuration. A precomputed write to the message mapping has the same effect.
The real Safe 1.3.0/1.4.0 tests exercise the actual signing libraries, handlers,
owner-signing control, and ERC-1271 return value, not merely mapping changes.

The existing blanket delegatecall policy blocks that library but also blocks
ordinary owner-initiated on-chain message signing. It is not a selective
message-authorization policy. Whether owner signing, module signing, or particular
message domains remain allowed must be decided before adopting a stricter policy.
No heuristic mapping-key check or implicit signing ban is added here.
