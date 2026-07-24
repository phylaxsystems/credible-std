# Examples

This folder contains assertion examples for credible-std across many protocols, consolidated from per-protocol git branches.

Each subfolder is compiled standalone via a Foundry profile that reuses the root `src/` (credible-std) and `lib/` (forge submodules) — there are no nested Foundry projects, only profiles in the root `foundry.toml`.

## Build a specific protocol

```sh
FOUNDRY_PROFILE=<protocol> forge build
```

## Protocols

| Folder | Source branch | Highlights |
|---|---|---|
| `aave/` | `aave` | Aave V3 Horizon oracle & reserve-backing; Aave V4 hub/spoke |
| `aerodrome/` | `aerodrome` | Aerodrome pool assertions |
| `balancer/` | — | Balancer V3 singleton Vault: hookless-pool swap invariant non-decrease + live tokenOut direction + pinned in-call rates, per-pool custody bound (necessary, not sufficient), scoped rate-provider drift bound, Vault net-outflow breaker |
| `cap/` | `cap` | OFAC and OFT adapters; fixed-dollar mint/redemption policies are quarantined |
| `curve/` | `curve` | crvUSD controller, LlamaLend, CurveLlamma, StableSwap-NG, TriCrypto-NG |
| `denaria/` | `all-protection-suites` | Legacy Denaria reference adapter; current Stylus deployment triggers are quarantined |
| `euler/` | `eulerv2` | EVault storage, call-scoped share-price, and ERC-4626 state-effect checks |
| `fluid/` | `fluid` | Fluid persisted-price, flow-policy, fToken, and vault-configuration checks |
| `kyber/` | `kyber` | Kyber receiver min-return checks, version-split by router family |
| `lido/` | `lido` | EasyTrack historical-snapshot voting check; incompatible universal vault adapters are quarantined |
| `lighter/` | `lighter` | Lighter active, rollback, and desert-mode bridge state machine |
| `mellow/` | `mellow` | Narrow subvault exit-liquidity policy; noncausal report, RiskManager, and flow checks are quarantined |
| `nado/` | `ink/assertions` | Nado perpetual clearinghouse |
| `royco/` | `royco-dawn` | Royco kernel accounting and version-neutral tranche state effects |
| `safe/` | `safe-protection-suite` | Safe config lock + tx-shape assertions |
| `safe-guard/` | `safe-guard` | Real Safe integration for `CredibleSafeGuard` |
| `spark/` | `spark` | Spark Vault previews/take accounting and risk-increasing SparkLend oracle guard |
| `symbiotic/` | `symbiotic` | Symbiotic V1 deposit/withdraw/claim/slash accounting; relay and noncausal circuit policy quarantined |
| `tydro/` | `ink/assertions` | Tydro Aave-v3-like operation safety on Ink |
| `uniswap/` | `0x` | Uniswap V3 pool assertions (V4 lives in root `src/`) |
| `veda/` | `ink/assertions` | Veda BoringVault assertions |
| `zeroex/` | `0x` | 0x Settler assertion |

Existing example projects on master (`assertions-book/`, `micro-patterns/`, `vault_demo/`) are unchanged.
