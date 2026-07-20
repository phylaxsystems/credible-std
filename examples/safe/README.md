# safe examples

Assertion examples and supporting helpers extracted from the `safe-protection-suite` branch.

## Build

```sh
FOUNDRY_PROFILE=safe forge build
```

## Files

- SafeConfigLockAssertion.sol
- SafeConfigLockHelpers.sol
- SafeTxShapeAssertion.sol
- SafeTxShapeHelpers.sol

`SafeTxShapeAssertion` expands configured CALL and DELEGATECALL batch executors, rejects packed
zero-address targets, and disables signed gas refunds because refund-token and refund-recipient
effects are outside its direct action tuple.
