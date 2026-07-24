# zeroex examples

Assertion examples and supporting helpers extracted from the `0x` branch.

## Build

```sh
FOUNDRY_PROFILE=zeroex forge build
```

## Files

- ZeroExSettlerAssertion.sol
- ZeroExSettlerHelpers.sol
- ZeroExSettlerInterfaces.sol
- ZeroExSettlerMainnetSwapIntrospectionAssertion.sol
- ZeroExSettlerMainnetSwapIntrospectionCodec.sol
- ZeroExSettlerMainnetSwapIntrospectionHelpers.sol

`ZeroExSettlerMainnetSwapIntrospectionAssertion` is intentionally quarantined and registers no
triggers. Its parser is retained as research code, not as a deployable protocol guard.
