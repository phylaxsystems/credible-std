# Uniswap examples

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Protocol-specific assertion examples and supporting helpers.

## Build and test

```sh
FOUNDRY_PROFILE=uniswap forge build
FOUNDRY_PROFILE=uniswap pcl test
```

## Files

- [UniswapV3PoolAssertion.sol](src/UniswapV3PoolAssertion.sol)
- [UniswapV3PoolHelpers.sol](src/UniswapV3PoolHelpers.sol)
- [UniswapV3PoolInterfaces.sol](src/UniswapV3PoolInterfaces.sol)
