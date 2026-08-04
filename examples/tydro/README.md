# tydro examples

Assertion examples for the Tydro deployment on Ink.

The adapter is pinned to the explorer-verified revision-11 L2 Pool at
`0x6a056dA055C616cd89dBcd0dC4b3f4E0F6162eb6`. Its five-argument
`finalizeTransfer`, compact amount sentinels, collateral flag, and liquidation
receive mode intentionally follow that verified implementation. Do not attach
this adapter to a different Pool revision based on ABI resemblance alone.

## Build

```sh
FOUNDRY_PROFILE=tydro forge build
```

## Files

- TydroOperationSafety.sol
