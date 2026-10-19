# Policy metadata v1

source-of-truth.json identifies the public GitHub repository, branch/ref and
indexFile. The dApp resolves the ref once per synchronization, then reads every
listed path at that commit. It never executes remote code or reads a moving branch
file-by-file.

index.json contains schemaVersion: 1 and a unique, nonempty metadataFiles array. Each entry points to `policy-catalog/policies/<slug>/metadata.json`.
Each manifest contains:

- template: stable slug, display name, summary, category, compatible target types
  and owner team.
- version.parameterSchema: ordered UI inputs. Every input has a stable key,
  label, description, type, required flag, editability and type-specific limits.
- version.applicabilityRules, dependency/conflict rules, coverage, residual risks
  and required integration mode.
- version.sourceRepository, exact sourceCommit, sourceBundleKey and pinned
  credibleStdCommit.
- version.compilerMetadata and testEvidence, including an explicit
  productionQualified: false until a reviewed publication gate is complete.
- bindings[]: one or more assertion deployments. Each binding declares the
  contract, source paths, constructor ABI/signature, positional argument bindings,
  expected assertion functions, expected trigger families, a `bytecodeFile` that
  points to the colocated canonical creation bytecode, the inline `baseBytecode`
  compatibility value, compiler settings and supported profiles.

Every policy directory contains `policy.sol`, `metadata.json`, and `bytecode.bin`.
The bytecode file is UTF-8 text containing the `0x`-prefixed creation bytecode
without constructor arguments. It is generated from the pinned Foundry artifact;
the catalog checker rejects a missing or mismatched file.

argumentBindings connect constructor arguments to policy_parameter values,
target bindings, reviewed relationships, integration values or constants. Their
solidityType must match the constructor ABI at the same position. Composite
ABI values use JSON in the UI; integer values use decimal strings to avoid
JavaScript precision loss. Type limits are UI constraints, not substitutes for
constructor simulation or protocol-specific review.

The current source-derived policies expose these constructor inputs:

| Policy | Inputs |
| --- | --- |
| Token Outflow Circuit Breaker | token, threshold bps, rolling window, optional minimum outflow floor, per-transaction cap (zero = hard stop) |
| Upgrade Governance Slot Lock | protected EIP-1967 proxy |
| Safe Configuration Policy | owners, threshold, singleton, fallback handler, transaction guard |
| Safe Action Policy | batch executors, internal address set, call rules, calldata pins, approval caps, maximum native value |
| Safe Outflow Circuit Breaker | token, rolling window, absolute outflow limit |

The metadata names the public Derive/Lighter commits used as upstream design
provenance. It does not claim either project approved these generalized templates.
Publication and activation require source review, negative/boundary/fork evidence,
integration checks, and explicit authority.
