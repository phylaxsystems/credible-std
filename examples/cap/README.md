# cap examples

Assertion examples and supporting helpers for the Cap protocol (cUSD / stcUSD).

## Build & test

```sh
FOUNDRY_PROFILE=cap forge build
FOUNDRY_PROFILE=cap pcl test
```

## Files

### Backing conservation — no infinite mint of cUSD

- `CapMintBackingAssertion.sol` — cUSD supply must stay covered by oracle-valued backing
  (`Σ totalSupplies(asset) * price(asset)`) on every mint/burn/redeem, plus a cumulative-inflow
  circuit breaker that rejects unaccounted reserve donations/stuffing.
- `CapMintBackingHelpers.sol` — fork-aware reads and USD valuation (cUSD valued at its $1 face
  peg, not the self-referential CapToken oracle).
- `CapMintBackingInterfaces.sol`

### Cross-chain backing — keep the OFT lockbox honest

- `CapOFTLockboxBackingAssertion.sol` — on the home chain, locked cUSD may leave the `OFTLockbox`
  (LayerZero `OFTAdapter`) only through a verified endpoint `lzReceive`, so remote `L2Token`
  supply can never be left unbacked by a drained lockbox.
- `CapOFTLockboxInterfaces.sol`

### Existing examples

- `CapOfacComplianceAssertion.sol` / `CapOfacComplianceInterfaces.sol` — sanctions screening.
- `CapRedemptionGateAssertion.sol` / `CapRedemptionGateInterfaces.sol` — tiered bank-run outflow gate.
