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
| `balancer/` | — | Balancer V3 singleton Vault: swap invariant non-decrease + BPT supply freeze, custody-vs-reserves-vs-pool-accounting envelope, rate-provider drift bound, Vault outflow breaker |
| `cap/` | `cap` | OFAC compliance + redemption-gate (ERC-4626) |
| `curve/` | `curve` | crvUSD controller, LlamaLend, CurveLlamma, StableSwap-NG, TriCrypto-NG |
| `denaria/` | `all-protection-suites` | Denaria perpetual operation safety |
| `euler/` | `eulerv2` | EVault, circuit breaker, sandwich detection |
| `lido/` | `lido` | Lido stETH vaults (generic): withdrawable-stETH buffer floor + outflow breaker, position risk regime, depeg gates, rate-vs-NAV |
| `mellow/` | `mellow` | Mellow flexible-vaults compromised-curator suite: vault outflow breaker, immutable oracle-report drift cap, RiskManager balance-correction containment, subvault allocation-health (no allocating into illiquid markets) |
| `nado/` | `ink/assertions` | Nado perpetual clearinghouse |
| `royco/` | `royco-dawn` | Royco kernel accounting, cumulative flow, vault tranche |
| `safe/` | `safe-protection-suite` | Safe config lock + tx-shape assertions |
| `spark/` | `spark` | Spark vault + SparkLend oracle/SLL inflow |
| `symbiotic/` | `symbiotic` | Symbiotic vault (flow, config, circuit breaker) + relay |
| `tydro/` | `ink/assertions` | Tydro Aave-v3-like operation safety on Ink |
| `uniswap/` | `0x` | Uniswap V3 pool assertions (V4 lives in root `src/`) |
| `veda/` | `ink/assertions` | Veda BoringVault assertions |
| `zeroex/` | `0x` | 0x Settler assertion |

Existing example projects on master (`assertions-book/`, `micro-patterns/`, `vault_demo/`) are unchanged.
