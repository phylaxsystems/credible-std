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
