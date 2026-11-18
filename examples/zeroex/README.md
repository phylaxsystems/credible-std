# 0x Settler examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Protocol-specific assertion examples and supporting helpers.

## Build and test

```sh
FOUNDRY_PROFILE=zeroex forge build
FOUNDRY_PROFILE=zeroex pcl test
```

## Files

- [ZeroExSettlerAssertion.sol](src/ZeroExSettlerAssertion.sol)
- [ZeroExSettlerHelpers.sol](src/ZeroExSettlerHelpers.sol)
- [ZeroExSettlerInterfaces.sol](src/ZeroExSettlerInterfaces.sol)
- [ZeroExSettlerMainnetSwapIntrospectionAssertion.sol](src/ZeroExSettlerMainnetSwapIntrospectionAssertion.sol)
- [ZeroExSettlerMainnetSwapIntrospectionCodec.sol](src/ZeroExSettlerMainnetSwapIntrospectionCodec.sol)
- [ZeroExSettlerMainnetSwapIntrospectionHelpers.sol](src/ZeroExSettlerMainnetSwapIntrospectionHelpers.sol)

`ZeroExSettlerMainnetSwapIntrospectionAssertion` is intentionally quarantined and registers no
triggers. Its parser is retained as research code, not as a deployable protocol guard.
