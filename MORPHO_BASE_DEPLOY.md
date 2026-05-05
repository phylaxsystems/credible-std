# MetaMorpho ERC-4626 Assertion — Base Mainnet Deployment Handoff

Top 5 MetaMorpho vaults on Base by TVL, with the ERC-4626 assertion bundle wired up per vault. Each instance is its own deployment — adopter is the vault.

## Adopter

Each assertion instance attaches to a **different** adopter — the MetaMorpho vault itself (the ERC-4626 contract).

| Field | Value |
|---|---|
| Chain | Base (chainId `8453`) |
| Assertion contract | `MetaMorphoVaultAssertion` (recommended — see "Bundle composition" below) |
| Assertion constructor | `(address vault_, address asset_, uint256 sharePriceToleranceBps_, uint256 outflowThresholdBps_, uint256 outflowWindow_)` |

Deploy 5 separate instances, one per vault, each constructed with the corresponding `(vault_, asset_)` pair below.

> ⚠️ **Do not use `GenericErc4626Bundle`.** That bundle inherits `ERC4626AssetFlowAssertion`, which checks `Δ totalAssets == net ERC-20 flow into the vault address`. MetaMorpho forwards deposited assets into Morpho Blue markets in the same call, so the vault's ERC-20 balance stays ≈ 0 while `totalAssets()` (which reads from Morpho) grows — the equality always fails. `SparkVaultAssertion` documents the same reason for excluding `AssetFlow`. Use a bundle composed of `ERC4626SharePriceAssertion + ERC4626PreviewAssertion + ERC4626CumulativeOutflowAssertion` only.

## Bundle composition (`MetaMorphoVaultAssertion`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {ERC4626BaseAssertion} from "credible-std/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626SharePriceAssertion} from "credible-std/protection/vault/ERC4626SharePriceAssertion.sol";
import {ERC4626PreviewAssertion} from "credible-std/protection/vault/ERC4626PreviewAssertion.sol";
import {ERC4626CumulativeOutflowAssertion} from "credible-std/protection/vault/ERC4626CumulativeOutflowAssertion.sol";

contract MetaMorphoVaultAssertion is
    ERC4626SharePriceAssertion,
    ERC4626PreviewAssertion,
    ERC4626CumulativeOutflowAssertion
{
    constructor(
        address vault_,
        address asset_,
        uint256 sharePriceToleranceBps_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindow_
    )
        ERC4626BaseAssertion(vault_, asset_)
        ERC4626SharePriceAssertion(sharePriceToleranceBps_)
        ERC4626CumulativeOutflowAssertion(outflowThresholdBps_, outflowWindow_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        _registerSharePriceTriggers();
        _registerPreviewTriggers();
        _registerCumulativeOutflowTriggers();
    }
}
```

## Token addresses (Base)

| Symbol | Address | Decimals |
|---|---|---|
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 |
| WETH | `0x4200000000000000000000000000000000000006` | 18 |

## Vaults (top 5 by TVL on Base — verified via api.morpho.org)

### 1. Steakhouse Prime USDC

| Field | Value |
|---|---|
| Vault (adopter) | `0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2` |
| Share symbol | `steakUSDC` |
| Underlying asset | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| Curator | Steakhouse Financial |

### 2. Gauntlet USDC Prime

| Field | Value |
|---|---|
| Vault (adopter) | `0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61` |
| Share symbol | `gtUSDCp` |
| Underlying asset | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| Curator | Gauntlet |

### 3. Steakhouse USDC

| Field | Value |
|---|---|
| Vault (adopter) | `0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183` |
| Share symbol | `steakUSDC` |
| Underlying asset | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| Curator | Steakhouse Financial |

### 4. Pangolins USDC

| Field | Value |
|---|---|
| Vault (adopter) | `0x1401d1271C47648AC70cBcdfA3776D4A87CE006B` |
| Share symbol | `pUSDC` |
| Underlying asset | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |

### 5. Froge's USDC

| Field | Value |
|---|---|
| Vault (adopter) | `0x2C6D169782bF18Cc634D076Fe639092227B82fdA` |
| Share symbol | `frUSDC` |
| Underlying asset | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |

> Top 5 by TVL is all-USDC at the time of writing. If you want WETH coverage in the bundle, the largest WETH vault on Base is **Moonwell Flagship ETH** at `0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1`, asset `0x4200000000000000000000000000000000000006` (WETH).

## Constructor argument tuples (Solidity)

Defaults below match the `ERC4626BaseAssertion` example: 50 bps share-price tolerance, 10% (1000 bps) cumulative outflow threshold over a rolling 24h window. Tune per-vault if needed.

```solidity
// 1. Steakhouse Prime USDC
new MetaMorphoVaultAssertion(
    0xBEEFE94c8aD530842bfE7d8B397938fFc1cb83b2, // vault_
    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // asset_  (USDC)
    50,                                         // sharePriceToleranceBps_   (0.5%)
    1_000,                                      // outflowThresholdBps_      (10% of TVL)
    24 hours                                    // outflowWindow_
);

// 2. Gauntlet USDC Prime
new MetaMorphoVaultAssertion(
    0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61,
    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
    50,
    1_000,
    24 hours
);

// 3. Steakhouse USDC
new MetaMorphoVaultAssertion(
    0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183,
    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
    50,
    1_000,
    24 hours
);

// 4. Pangolins USDC
new MetaMorphoVaultAssertion(
    0x1401d1271C47648AC70cBcdfA3776D4A87CE006B,
    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
    50,
    1_000,
    24 hours
);

// 5. Froge's USDC
new MetaMorphoVaultAssertion(
    0x2C6D169782bF18Cc634D076Fe639092227B82fdA,
    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
    50,
    1_000,
    24 hours
);
```

## Triggers wired up by the bundle

The bundle inherits three trigger groups; for each adopter (vault) the executor will run the listed assertions on the listed selectors:

| Assertion fn | Trigger kind | Selectors |
|---|---|---|
| `assertSharePriceEnvelope` | `registerTxEndTrigger` | tx-end |
| `assertPerCallSharePrice` | `registerFnCallTrigger` | `deposit`, `mint`, `withdraw`, `redeem` |
| `assertDepositPreview` | `registerFnCallTrigger` | `deposit` |
| `assertMintPreview` | `registerFnCallTrigger` | `mint` |
| `assertWithdrawPreview` | `registerFnCallTrigger` | `withdraw` |
| `assertRedeemPreview` | `registerFnCallTrigger` | `redeem` |
| `assertCumulativeOutflow` | `watchCumulativeOutflow` | `asset` outflow vs. TVL over `outflowWindow_` |

ERC-4626 selectors:

| Function | Selector |
|---|---|
| `deposit(uint256,address)` | `0x6e553f65` |
| `mint(uint256,address)` | `0x94bf804d` |
| `withdraw(uint256,address,address)` | `0xb460af94` |
| `redeem(uint256,address,address)` | `0xba087652` |

## Known caveats specific to MetaMorpho

1. **`totalAssets()` is computed, not held.** The vault holds Morpho Blue market shares, not the underlying asset. `ERC4626AssetFlowAssertion` is therefore unsafe — it is omitted in the bundle above by design.

2. **Skim / fee accrual.** MetaMorpho mints performance-fee shares to `feeRecipient` inside `_accrueFee` on each deposit/withdraw. This dilutes existing holders by the fee fraction; share-price tolerance must be ≥ the largest expected per-call fee mint. 50 bps is comfortable for current performance fees (≤ 25%) under normal interest accrual. If a vault uses a higher fee or large rate jumps are expected, raise `sharePriceToleranceBps_`.

3. **`reallocate()` (curator-only) does not touch user shares** but reshuffles assets across Morpho markets. It is not in the standard ERC-4626 selector set, so the bundle does not trigger on it. If you also want safety checks on reallocation (e.g., supply-cap respect), extend the bundle with `registerFnCallTrigger(... , bytes4(keccak256("reallocate((address,uint256)[])")))`.

4. **Public allocator path.** When the public allocator (`0xfd32fA2ca22c76dD6E550706Ad913FC6CE91c75D`) is invoked it calls `reallocate` via the vault's `IPublicAllocator` allowlist; same caveat as (3).

5. **All five top-TVL vaults share the same underlying (USDC).** If you need WETH or cbBTC coverage, swap a USDC vault for `Moonwell Flagship ETH` (see note above the constructors).

## Verification

Vault list, share symbols, underlying asset addresses, and TVL ranking pulled from the official Morpho GraphQL API:

```bash
curl -s -X POST 'https://api.morpho.org/graphql' \
  -H 'Content-Type: application/json' \
  -d '{"query":"query { vaults(first: 12, where: { chainId_in: [8453], totalAssetsUsd_gte: 1000000 }, orderBy: TotalAssetsUsd, orderDirection: Desc) { items { address symbol name asset { address symbol decimals } state { totalAssetsUsd } } } }"}'
```

Each vault address can be cross-checked on Basescan (`https://basescan.org/address/<vault>`) — the contract page shows `MetaMorpho` as the implementation and `asset()` matches the address listed above.
