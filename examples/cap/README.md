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

### Liquidations — debt is repaid, proceeds stay in the protocol

- `CapLiquidationAssertion.sol` — deployed against the `Lender`. A liquidation that moves value
  must strictly reduce the borrower's debt for the liquidated asset (no seizing collateral without
  repaying debt), and the vault's claimable backing (`availableBalance = totalSupplies -
  totalBorrows`) may not fall below its pre-call value minus the restaker interest the liquidation
  legitimately realizes (proceeds stay in the protocol as backing rather than draining the vault).
  Each check is scoped per `liquidate` call via PreCall/PostCall snapshots.
- `CapLiquidationHelpers.sol` — triggered-call resolution and fork-aware reads (all in asset units).
- `CapLiquidationInterfaces.sol`

### Cross-chain backing — keep the OFT lockbox honest

- `CapOFTLockboxBackingAssertion.sol` — on the home chain, locked cUSD may leave the `OFTLockbox`
  (LayerZero `OFTAdapter`) only through a verified endpoint `lzReceive`, so remote `L2Token`
  supply can never be left unbacked by a drained lockbox.
- `CapOFTLockboxInterfaces.sol`

### Existing examples

- `CapOfacComplianceAssertion.sol` / `CapOfacComplianceInterfaces.sol` — sanctions screening.
- `CapRedemptionGateAssertion.sol` / `CapRedemptionGateInterfaces.sol` — tiered bank-run outflow gate.
