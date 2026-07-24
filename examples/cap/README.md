# cap examples

Assertion examples and supporting helpers for the Cap protocol (cUSD / stcUSD).

## Build & test

```sh
FOUNDRY_PROFILE=cap forge build
FOUNDRY_PROFILE=cap pcl test
```

Requires `pcl` >= 1.4.0. These assertions register cumulative-flow triggers and use the
`getLogsForCall` precompile; older builds fail during assertion setup with
`Fn selector not found` / `Precompile selector not found` and execute 0 tests.
Verified with `pcl` 1.4.0 (commit `a600e1d`).

## Files

### Quarantined policy prototypes

- `CapMintBackingAssertion.sol` — currently registers no triggers. Its fixed-$1 valuation conflicts
  with Cap's NAV conversions and its static reserve list cannot follow the live Vault asset set.
- `CapMintBackingHelpers.sol` — fork-aware reads and USD valuation (cUSD valued at its $1 face
  peg, not the self-referential CapToken oracle).
- `CapMintBackingInterfaces.sol`
- `CapRedemptionGateAssertion.sol` — currently registers no triggers. Strategy divest inflows net
  against redemption outflows in the executor, while the watcher denominator is idle custody.

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
  `OFTLockbox` (LayerZero `OFTAdapter`) must be covered by endpoint-driven `lzReceive` calls, each
  credited at `min(message-authorized amount, amount actually released inside the call)`. Capping by
  the decoded OFT message amount binds the release to what the remote chain verifiably burned (a
  faulty/upgraded adapter over-releasing trips); the in-call release floor gates success (a reverted
  receive credits nothing). A drain therefore cannot ride alongside an unrelated, reverted, or
  dust-sized bridge-in and leave remote `L2Token` supply unbacked.
- `CapOFTLockboxInterfaces.sol`

### Existing examples

- `CapOfacComplianceAssertion.sol` / `CapOfacComplianceInterfaces.sol` — sanctions screening using
  an explicitly configured on-chain oracle. Address arguments are decoded from the low 160 bits of
  their ABI words.

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
