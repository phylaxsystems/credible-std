# Assertion examples

Start with [micro-patterns](micro-patterns/) for small, focused policies or the
[vault demo](vault_demo/) for tests that compare protected and vulnerable behavior.
The [Assertions Book](assertions-book/) supplies documentation snippets. Protocol
folders show how policies depend on a particular interface, accounting model, and
trigger scope; read their limitations before adapting them.

**Passing tests do not make an example a production-ready adapter.** A quarantined
wrapper registers no triggers and provides no protection. Some tests deliberately
exercise research harnesses or confirm that unsafe wrappers stay disabled.

## Setup and checks

From the repository root, install [Foundry](https://getfoundry.sh/) and
[PCL 1.6.0](https://github.com/phylaxsystems/pcl/releases/tag/1.6.0), then initialize
the pinned dependencies:

```sh
git submodule update --init --recursive

# Check formatting, build, and test every example (also used by CI; requires jq).
./scripts/check_examples.sh

# Check one profile, including evidence that its assertions executed.
./scripts/check_examples.sh micro-patterns

# Build or debug a specific profile directly.
FOUNDRY_PROFILE=micro-patterns forge build
RUST_MIN_STACK=16777216 FOUNDRY_PROFILE=micro-patterns pcl test -vvvv
```

Use `pcl test` for tests that arm `cl.assertion`; stock `forge test` cannot execute
that cheatcode. The larger Rust thread stack matches CI. Root `forge test` does
not include the separate example profiles.

Profiles are defined in the root `foundry.toml` and share root `src/` and `lib/`.
The `vault_demo/` directory uses profile `vault-demo`. The deployment-specific
[Aave staging project](aave/credible/) is a separate nested project, not a generic
example or part of the root Aave profile; its pinned configuration is not an
instruction to deploy it.

## Choose an example

“Runtime” means the suite executes at least one assertion through PCL. It does
not mean every contract or trigger in that folder is covered. “Quarantine/setup”
means the current tests check disabled wrappers, construction, or pure helpers,
with no runtime assertion execution. “Build” means there is no dedicated test suite.

| Example / profile | Focus and limitations | Check |
|---|---|---|
| [micro-patterns](micro-patterns/) | Seven policy sketches; participant screening has focused regression tests | Runtime |
| [vault-demo](vault_demo/) | Intentionally vulnerable vault and curator scenarios | Runtime |
| [assertions-book](assertions-book/) | Documentation assertions and mock protocols | Build |
| [aave](aave/) | V3 Horizon and V4 oracle checks; several hub/spoke wrappers quarantined | Runtime |
| [aerodrome](aerodrome/) | Pool reserve/accounting checks | Runtime |
| [balancer](balancer/) | V3 singleton Vault, hookless swaps, custody bounds, and flow policy | Runtime |
| [cap](cap/) | Quarantined policies and adapter construction checks | Quarantine/setup |
| [curve](curve/) | crvUSD, LlamaLend, LLAMMA, StableSwap-NG, and TriCrypto-NG | Runtime |
| [denaria](denaria/) | Legacy Solidity reference; current Stylus deployment unsupported | Runtime |
| [euler](euler/) | EVault user-storage accounting; full bundle and share-price wrapper quarantined | Runtime |
| [fluid](fluid/) | Persisted exchange-price monotonicity, flow policy, fToken pricing, and vault configuration | Runtime |
| [kyber](kyber/) | Receiver min-return checks split by router version | Runtime |
| [lido](lido/) | EasyTrack snapshot check; generic vault prototypes quarantined | Runtime |
| [lighter](lighter/) | Quarantined bridge state-machine wrapper and outflow policy | Quarantine/setup |
| [mellow](mellow/) | Subvault exit-liquidity policy; report, risk-manager, and flow checks quarantined | Runtime |
| [nado](nado/) | Perpetual clearinghouse operation checks | Runtime |
| [royco](royco/) | Narrow kernel bundle; tranche-operation wrapper quarantined | Quarantine/setup |
| [safe](safe/) | Configuration lock and transaction shape | Runtime |
| [spark](spark/) | Vault accounting; SparkLend oracle guard quarantined | Runtime |
| [symbiotic](symbiotic/) | Vault prototypes and operator policy; bundled wrappers quarantined | Quarantine/setup |
| [tydro](tydro/) | Operation safety for the documented revision-11 L2 Pool | Runtime |
| [uniswap](uniswap/) | V3 pool checks; V4 examples live under root `src/protection/swaps/` | Runtime |
| [veda](veda/) | BoringVault asset movement and authorized share-only burns | Runtime |
| [zeroex](zeroex/) | Settler checks; mainnet introspection prototype quarantined | Runtime |

## Adapting and contributing

- State the policy's assumptions: protocol version, adopter, units, selectors,
  custody model, and whether it is an invariant or an operator-selected limit.
- Read protocol state at the intended transaction/call snapshot. Assertion-local
  state is separate; use the fork-aware helpers for external contract reads.
- Include an allowed operation, a violating operation with the exact expected
  revert, and relevant boundary or batching cases. A test that only deploys an
  assertion does not demonstrate protection.
- Keep quarantine notices next to the affected code and in its README. Do not
  enable a wrapper just to make a runtime-coverage check pass.
- Add a root Foundry profile matching the folder name. CI discovers every
  top-level example folder; update the check script's explicit classifications
  when adding or enabling a build-only or quarantined example.
