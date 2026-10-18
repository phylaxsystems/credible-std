# Policy metadata v1

The consumer config chooses a GitHub `repository`, `ref` (branch, tag, or commit),
and `indexFile`. Resolve the ref once per synchronization, then read all files
at that resolved commit. Never fetch individual files from a moving branch.

`index.json` contains `schemaVersion: 1` and a nonempty, unique `manifests` array
of repository-relative JSON paths. Only listed manifests belong to the catalog.
Each manifest contains:

| Field | Consumer behavior |
| --- | --- |
| `schemaVersion` | Reject unsupported versions. Currently `1`. |
| `template` | Stable `slug`, display `name`, `summary`, `category`, compatible `targetTypes`, `ownerTeam`. |
| `version.semanticVersion` | Immutable version identifier once published. |
| `version.parameterSchema` | Ordered input definitions: stable `key`, `label`, `description`, `type`, `required`, `customerEditable`, optional defaults/recommendations and type-specific constraints. |
| `version.applicabilityRules` | Supported profiles, required relationships and disallowed integration modes. |
| `version.dependencyRules`, `version.conflictRules` | Desired-state requirements; these are not Solidity guarantees. |
| `version.coverageStatement`, `version.residualRisks` | Explain intended protection and its limits. |
| `version.requiredIntegration` | Integration modes required before activation. |
| `version.sourceRepository`, `version.sourceCommit` | Exact repository and commit containing the source artifacts. |
| `version.credibleStdCommit` | Pinned standard-library revision used to flatten the sources. |
| `version.compilerMetadata`, `version.testEvidence` | Reproducible compiler settings and explicitly scoped test results. |
| `version.publicationStatus` | Authored entries are `draft`; repository sync does not publish. |
| `bindings[]` | One entry per assertion deployment; a policy can deploy multiple assertions, each with multiple assertion functions. |

Each binding declares `contractName`, `sourcePath`, flattened `sourceFile`,
`flattenedSourceKey`, constructor ABI/signature, `argumentBindings`,
`expectedAssertionSpec.assertionFunctions`, `expectedTriggers`, compiler settings,
compiled `baseBytecode`, `targetBindingRole`, and `supportedTargetProfiles`.

`argumentBindings` are positional, in constructor order. Each has an
`argumentName`, canonical `solidityType`, `source`, and `transform`. Sources are
`policy_parameter` (by key), `target_address`, `target_snapshot`,
`relationship_address`, `integration_value`, or a reviewed `constant`.
Target-derived sources identify a `targetBindingRole`. Never guess a missing
secondary target. Reject unresolved values and constructor type/count mismatches.

Parameter types include `address`, `address_list`, `uint`, `percentage_bps`,
`duration_seconds`, `duration_blocks`, `asset_amount`, `boolean`, `enum`, `bytes`,
`selector_set`, target/role references, and structured rule types. `abi` provides
an escape hatch for explicitly declared Solidity types (including tuples and
arrays): scalar inputs use text and composite inputs use JSON. Solidity integer
values are decimal strings to avoid JavaScript precision loss. UI min/max values
do not express every constructor invariant: compilation/constructor simulation
must also enforce cross-field constraints such as soft threshold < hard threshold.

The initial templates' trigger labels describe registration families:
`cumulativeOutflow`, `functionCall`, `storageChange`, and `txEnd`. They are not
execution receipts. Function lists are checked against the compiled ABI.

The dApp's catalog validator is the strict consumer contract. Unknown or malformed
input must fail before any database publication or deployment. Never execute
scripts supplied by a remote catalog during synchronization.
