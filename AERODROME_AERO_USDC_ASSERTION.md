# Aerodrome AERO/USDC Pool Assertion

Base mainnet AERO/USDC Aerodrome pool:

```solidity
address constant AERO_USDC_POOL = 0x6CDCb1C4A4D1C3C6d054b27AC5B77e89eAfB971d;
address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
```

Attach `AerodromePoolAssertion` to the pool address. The constructor metadata is:

```solidity
AerodromePoolAssertion(
    AERO_USDC_POOL,
    USDC,    // token0
    AERO,    // token1
    false,   // volatile pool
    1e6,     // token0 decimals scale: USDC
    1e18     // token1 decimals scale: AERO
)
```

Registration create data:

```solidity
bytes memory createData = abi.encodePacked(
    type(AerodromePoolAssertion).creationCode,
    abi.encode(
        AERO_USDC_POOL,
        USDC,
        AERO,
        false,
        uint256(1e6),
        uint256(1e18)
    )
);
```

ABI-encoded constructor args:

```text
0x0000000000000000000000006cdcb1c4a4d1c3c6d054b27ac5b77e89eafb971d000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000940181a94a35a4569e4529a3cdfb74e38fd98631000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000de0b6b3a7640000
```

Full deployment bytecode with constructor args appended:

```text
AERODROME_AERO_USDC_DEPLOY_BYTECODE.txt
```

The full initcode is 7,072 bytes.

Example assertion registration:

```solidity
cl.assertion({
    adopter: AERO_USDC_POOL,
    createData: createData,
    fnSelector: AerodromePoolAssertion.assertReservesMatchBalances.selector
});
```

`AerodromePoolAssertion.triggers()` wires the pool selectors to all bundled checks:

- `assertReservesMatchBalances`
- `assertSwapKNonDecreasing`
- `assertOracleStateMonotonic`
- `assertClaimFeesPreservesPoolLiquidity`
