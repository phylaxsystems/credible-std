# royco examples

Assertion examples and supporting helpers extracted from the `royco-dawn` branch.

The active bundle is narrowed to v1.2-compatible NAV conservation, ordinary non-bypass coverage,
self-liquidation deleveraging, and state-effect checks around tranche operations. The invalid
perpetual-health predicate, preview-to-preview recovery checks, v1.2 virtual-offset deposit formula,
and idle-balance cumulative-flow policies are not registered. Live mixed v1.2/v1.3 deployments
must still be version-bound before activation.

## Build

```sh
FOUNDRY_PROFILE=royco forge build
```

## Files

- RoycoHelpers.sol
- RoycoKernelAccountingAssertion.sol
- RoycoKernelAssertion.sol
- RoycoKernelCumulativeFlowAssertion.sol
- RoycoKernelCumulativeOutflowAssertion.sol
- RoycoVaultTrancheAssertion.sol
- RoycoVaultTrancheOperationAssertion.sol
