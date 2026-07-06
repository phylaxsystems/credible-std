# Summer.fi (Lazy Summer Protocol) — donation-to-Ark `totalAssets()` manipulation

Reproduction of the **2026-07-06 Summer.fi exploit** (~$6M) and a check of whether the
credible-std vault assertions catch it.

- Exploit tx: [`0x0db528c4…d43da12`](https://etherscan.io/tx/0x0db528c44f23fc7fa4544684a2fab81096450a14aae8bc89f42cd0592d43da12) (block 25471348)
- Primary victim vault: `LazyVault_LowerRisk_USDC` (`0x98c4…cf17`), a FleetCommander ERC-4626
- Manipulated Ark valuation token: `Varlamore USDC Growth` / vgUSDC (`0x8399…c78f`)
- Flash-loan source: Morpho Blue (`0xbbbb…ffcb`)

## Root cause

A FleetCommander's `totalAssets()` is the sum of a USDC buffer plus every **Ark**'s
`totalAssets()`. The Varlamore Ark derives its reported assets from the **live vgUSDC balance it
holds**, valued via `vgUSDC.convertToAssets(vgUSDC.balanceOf(ark))` — an on-chain balance, not
internally-tracked principal. (Verified on-chain: the recipient Ark `0x61d7…76c2` still holds the
donated `19,551,517,226.71` vgUSDC, and its `totalAssets()` == `convertToAssets(balance)` ==
`$7,237,968.83`.)

Because any address can raise that balance with a **direct token transfer ("donation")**, the
attacker inflated `FleetCommander.totalAssets()` mid-transaction with no matching share mint,
pumped the vault share price, and redeemed freshly-minted shares against the real USDC buffer at
the inflated price:

```
deposit 64.83M USDC  -> mint 60.79M shares  (share price ~1.0665, fair)
donate  19.55B vgUSDC -> Ark               (totalAssets jumps ~$7.2M, no shares minted)
redeem  60.77M shares -> 70.96M USDC        (share price ~1.1678, inflated) => ~+6M
```

## What's modelled here

`src/SummerProtocol.sol` reproduces the accounting shape with the smallest faithful surface:
a `FleetCommander` ERC-4626 whose `totalAssets()` = USDC buffer + `Ark.totalAssets()`, and an
`Ark` whose `totalAssets()` = the vgUSDC balance it holds. `src/SummerExploit.sol` runs
deposit → donate → redeem in one transaction. The prior manipulation that let the attacker obtain
vgUSDC below the Ark's face valuation is abstracted away (attacker is simply funded with vgUSDC);
the reproduced defect is the Ark counting a donatable external balance.

## Findings (`FOUNDRY_PROFILE=summer pcl test --offline`)

| Test | Result |
|---|---|
| `test_Baseline_ExploitProfits` | Exploit nets ~6.12M USDC; share price spikes ~9.4%; vault left unable to honor the honest LP. |
| `test_ShippedSharePriceEnvelope_TxEnd_Blocks` | **Shipped `ERC4626SharePriceAssertion` tx-end envelope reverts it** (`assetsMatchSharePrice`, all fork points). |
| `test_ShippedMetaMorphoBundle_Envelope_Blocks` | The full shipped `MetaMorphoVaultAssertion` bundle reverts it. |
| `test_ConvertToAssetsOracleSanity_TxEnd_Blocks` | A `convertToAssets` oracle-sanity guard (tx-end trigger) reverts it. |
| `test_CumulativeOutflowBreaker_Blocks` | The cumulative-outflow circuit breaker trips on the oversized redemption. |
| `test_PerCallSharePrice_CannotSeeOutOfCallDonation` | A per-call-only guard is blind: price is flat within each vault call; the jump happens on the out-of-call donation. |

### Takeaways

- The manipulation is **detectable at the transaction boundary**: a share-price envelope that
  checks `totalAssets/totalSupply` across all fork points catches the intra-tx spike.
- The trigger matters. A **tx-end (all-forks)** trigger catches it; a **per-call** check does not,
  because the donation is a plain ERC-20 transfer that never calls the vault. Likewise, an
  `fnCall`-on-`donate` trigger (as in `vault_demo`) would never fire — the donation targets the
  Ark, not the vault.
