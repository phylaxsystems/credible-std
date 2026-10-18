# Reusable policy library

This directory is the source of truth for constructor-configured policies consumed
by the Credible Layer dApp. The working branch is 'codex/policy-library'. The
initial catalog is intentionally limited to controls derived from the public
Derive and Lighter assertion packages.

## Catalog

- **Token Outflow Circuit Breaker** — one generic rolling-window token breaker
  combining Derive's floor/soft-cap/hard-stop behavior with Lighter's
  watchCumulativeOutflow bridge invariant.
- **Upgrade Governance Slot Lock** — one generic EIP-1967 implementation-slot
  policy based on Lighter's first protection lane and Derive's governance pin.
- **Safe Configuration Policy** — constructor-pinned owners, threshold, singleton,
  guard, fallback handler and module state, based on Derive's Safe config lock.
- **Safe Action Policy** — constructor-pinned target/selector rules, calldata pins,
  batch limits, approval caps and native-value cap, based on Derive's Safe action
  policy and the shared Lighter Safe policy surface.
- **Safe Outflow Circuit Breaker** — constructor-configured rolling token limit for
  Safe custody, based on Derive's Safe outflow breaker.

The former showcase policies (tiered outflow, oracle, settlement, and upgrade-gate
state-lock) were removed from this source of truth. They are not indexed or
available to the dApp.

## Author and verify

1. Edit sources/policy-assertions.sol and policy-catalog/test.
2. Regenerate the self-contained source bundle:
   forge flatten policy-catalog/sources/policy-assertions.sol -o policy-catalog/bundles/policy-assertions.sol.
3. Run FOUNDRY_PROFILE=policy-library forge test.
4. Add or update templates/<slug>/<version>.json and list it in index.json.
   Each manifest defines display fields, typed inputs, constructor bindings,
   assertion functions, trigger families, compatibility, risks and evidence.
5. Run python3 scripts/policy-catalog-artifacts.py after compilation, then
   python3 scripts/policy-catalog-artifacts.py --check.
6. Pin sourceCommit to the commit containing the exact source bundle and
   credibleStdCommit to the credible-std revision used to compile it.

The dApp points at this repository and branch, resolves the branch once, reads
policy-catalog/index.json, then validates all listed metadata and source files.
pnpm policy:sync records the resolved commit in a lock file. Synchronization
does not publish database rows or activate a release.

## Qualification

All manifests remain **draft**, with productionQualified: false. Compilation and
constructor tests do not establish PhEVM runtime, fork, integration, or production
qualification. Those gates must be completed before publication or activation.
