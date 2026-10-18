# Reusable policy library

This directory is the source of truth for constructor-configured policies consumed
by the Credible Layer dApp. The initial working branch is `codex/policy-library`.
A policy is assertion source plus UI/deployment metadata, not project-specific
Solidity generated in the browser.

## Initial policies

- Rolling token outflow breaker with a configurable armed transaction cap.
- Tiered token outflow breaker with soft and hard thresholds.
- Safe action policy with target, selector, batch, approval and module rules.
- Safe configuration lock with constructor-supplied expected configuration.
- Upgrade-gate state lock with configurable addresses, slots and trigger selector.
- Settlement integrity pin with configurable verifier, slots and selectors.

These generalize Derive/Lighter alignment controls. Safe-specific controls remain
explicitly typed; the library and release composer are not restricted to Safes.
See `source-of-truth.json` for upstream provenance and `FORMAT.md` for the metadata
contract. The oracle-policy showcase fixture has no source implementation and is
not included in this catalog.

## Author and verify

1. Edit `sources/policy-assertions.sol` and its constructor tests.
2. Regenerate the self-contained source bundle:
   `forge flatten policy-catalog/sources/policy-assertions.sol -o policy-catalog/bundles/policy-assertions.sol`.
3. Run `FOUNDRY_PROFILE=policy-library forge test`.
4. Add/update `templates/<slug>/<version>.json` and list it in `index.json`.
   Define display fields, input types, constructor bindings, assertion functions,
   triggers, compatibility, limits and evidence. Bump published versions rather
   than mutating them.
5. Run `python3 scripts/policy-catalog-artifacts.py` after compilation, then
   `python3 scripts/policy-catalog-artifacts.py --check`.
6. Pin `sourceCommit` to a commit containing the exact bundle and
   `credibleStdCommit` to the standard-library revision used to flatten it.
   Source and manifest commits may differ; this avoids self-referential hashes.

The dApp points at this repo/ref and reads `policy-catalog/index.json`. Its
`pnpm policy:sync` command fetches the ref once, validates all listed metadata and
sources, and records the resolved commit in a lock file. `pnpm policy:validate`
then validates the synchronized snapshot offline. Neither command publishes.

## Qualification

All initial manifests remain **draft**, with **productionQualified: false**.
Constructor tests and compilation are not runtime assertion protection evidence.
PhEVM execution, negative/boundary scenarios, fork tests, integration review and
explicit publication remain required. The settlement state-root lock intentionally
rejects state-root changes; it is not suitable for an ordinary settlement path
without a reviewed integration/use case.
