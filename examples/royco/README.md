# Royco examples

Protocol-specific assertion examples and supporting helpers.

The Kernel bundle is narrowed to v1.2-compatible NAV conservation, ordinary non-bypass coverage,
and self-liquidation deleveraging. The tranche operation wrapper is quarantined and registers no
triggers because share and return deltas do not prove the official asset movement. The invalid
perpetual-health predicate, preview-to-preview recovery checks, v1.2 virtual-offset deposit formula,
and idle-balance cumulative-flow policies are not registered. Live mixed v1.2/v1.3 deployments
must still be version-bound before activation.

## Build and test

```sh
FOUNDRY_PROFILE=royco forge build
FOUNDRY_PROFILE=royco pcl test
```

## Files

- [RoycoHelpers.sol](src/RoycoHelpers.sol)
- [RoycoKernelAccountingAssertion.sol](src/RoycoKernelAccountingAssertion.sol)
- [RoycoKernelAssertion.sol](src/RoycoKernelAssertion.sol)
- [RoycoKernelCumulativeFlowAssertion.sol](src/RoycoKernelCumulativeFlowAssertion.sol)
- [RoycoKernelCumulativeOutflowAssertion.sol](src/RoycoKernelCumulativeOutflowAssertion.sol)
- [RoycoVaultTrancheAssertion.sol](src/RoycoVaultTrancheAssertion.sol)
- [RoycoVaultTrancheOperationAssertion.sol](src/RoycoVaultTrancheOperationAssertion.sol)
