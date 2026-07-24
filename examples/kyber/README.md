# KyberSwap examples

This example targets MetaAggregationRouterV2. Kyber has two deployed runtime families at the shared
router address, so deployments must explicitly select whether the original `swapGeneric` surface
is present.

```sh
FOUNDRY_PROFILE=kyber forge build
FOUNDRY_PROFILE=kyber pcl test
```

Only `assertReceiverGetsMinReturn` is registered. It checks standard ERC-20, non-partial output by
comparing the declared receiver's balance before and after the exact swap call. The live router
already performs the same balance-delta check, so this is a narrow redundant postcondition. Native
output and original-family partial fills remain outside it. The original-family partial-fill flag
is not applied to modern deployments.

`assertNoThirdPartyAllowanceDrain` is retained as an unarmed diagnostic. A `Transfer` event does
not identify which spender used the allowance, so a route where an executor spends its own tokens
can be rejected merely because it has a stale router allowance. Approval events do not establish
causality either. The old approval behavior tests are therefore no longer part of the executable
semantic suite.

The configured router is bound to the adopter, but deployment operations must still pin the chain
and verified runtime family. The local route mocks are unit fixtures and do not reproduce every
live command encoding.
