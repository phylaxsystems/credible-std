# KyberSwap examples

This example targets MetaAggregationRouterV2. Kyber uses the same router address across chains but
has distinct verified runtime families, so the example exposes separate assertion artifacts:

- `KyberOriginalMetaAggregationRouterAssertion` includes `swapGeneric` and the original
  partial-fill semantics.
- `KyberModernMetaAggregationRouterAssertion` omits `swapGeneric` and never interprets caller bit
  zero as a partial-fill bypass.

The family is fixed by the selected bytecode artifact; there is no deployer-supplied family
boolean.

```sh
FOUNDRY_PROFILE=kyber forge build
FOUNDRY_PROFILE=kyber pcl test
```

Only `assertReceiverGetsMinReturn` is registered. It compares the declared receiver's balance
before and after the exact swap call. The live router already performs a receiver-delta check, so
this is a narrow redundant postcondition for a buggy or compromised settlement path, not a
universal protocol invariant.

The additive outer-call model excludes native output, same-token routes, and rebasing/reflection
tokens. On the original family, a partial-fill route is skipped only when native input or
`_SHOULD_CLAIM` can make the router recompute `spentAmount` below `desc.amount`; caller-controlled
bit zero alone does not disable the flat check. The modern artifact never applies partial-fill
semantics.

`assertNoThirdPartyAllowanceDrain` is retained as an unarmed diagnostic. A `Transfer` event does
not identify which spender used the allowance, so a route where an executor spends its own tokens
can be rejected merely because it has a stale router allowance. Approval events do not establish
causality either. The old approval behavior tests are therefore no longer part of the executable
semantic suite.

The configured router is bound to the adopter. Deployment operations must still pin the chain and
verified runtime family before choosing an artifact. The local model reproduces the accounting and
`swap` dispatch boundaries used by the semantic tests. Its `swapSimpleMode` cases are isolated
calldata/assertion-branch fixtures, not a reproduction of Kyber's full `SimpleSwapData` engine.
