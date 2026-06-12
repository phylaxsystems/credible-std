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

- `CapOFTLockboxBackingAssertion.sol` — on the home chain, the gross outflow of locked cUSD from the
  `OFTLockbox` (LayerZero `OFTAdapter`) must be covered by the amount actually released *inside*
  successful endpoint-driven `lzReceive` calls. This binds the released amount and recipient to a
  verified remote burn, so a drain cannot ride alongside an unrelated (or reverted) bridge-in and
  leave remote `L2Token` supply unbacked.
- `CapOFTLockboxInterfaces.sol`

### Existing examples

- `CapOfacComplianceAssertion.sol` / `CapOfacComplianceInterfaces.sol` — sanctions screening.
- `CapRedemptionGateAssertion.sol` / `CapRedemptionGateInterfaces.sol` — tiered bank-run outflow gate.

## Operational contract & open decisions

These examples carry two deliberate tradeoffs that Cap must own before production (also noted in
`CapMintBackingHelpers.sol`):

- **Fail-closed on read failure (decide with Cap).** Oracle/state reads revert on infra errors, so a
  transiently down/stale/zero oracle blocks mint/burn/redeem. Defensible for a solvency invariant
  (halt rather than allow an unbacked mint), but the alternative — fail-open on infra-level read
  failures while keeping the solvency comparison strict — is a valid choice. Pending Cap sign-off.
- **Static backing-asset set (must resolve before production).** `ASSET0..ASSET4` are fixed at deploy
  via immutables. Any reserve-set change silently under-counts backing and drops inflow coverage for
  the new asset. Before mainnet, either enforce a redeploy-on-reserve-change operational contract or
  drive the asset set from on-chain state.
