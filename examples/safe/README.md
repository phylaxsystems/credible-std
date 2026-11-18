# Safe examples

Protocol-specific assertion examples and supporting helpers.

## Build and test

```sh
FOUNDRY_PROFILE=safe forge build
FOUNDRY_PROFILE=safe pcl test
```

## Files

- [SafeConfigLockAssertion.sol](src/SafeConfigLockAssertion.sol)
- [SafeConfigLockHelpers.sol](src/SafeConfigLockHelpers.sol)
- [SafeTxShapeAssertion.sol](src/SafeTxShapeAssertion.sol)
- [SafeTxShapeHelpers.sol](src/SafeTxShapeHelpers.sol)

`SafeTxShapeAssertion` expands configured CALL and DELEGATECALL batch executors, rejects packed
zero-address targets, and disables signed gas refunds because refund-token and refund-recipient
effects are outside its direct action tuple.
