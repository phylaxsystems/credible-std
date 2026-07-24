# Mellow examples

These examples target Mellow `flexible-vaults` and are version-specific.

```sh
FOUNDRY_PROFILE=mellow forge build
FOUNDRY_PROFILE=mellow pcl test
```

## Release status

Three original policies are quarantined and register no triggers:

- `MellowVaultOutflowAssertion`: the executor observes net flow against the root Vault's idle
  balance. Subvault divests cancel payouts, routine strategy pushes look like exits, and native ETH
  has no ERC-20 `Transfer` log.
- `MellowRiskManagerBalanceAssertion`: `modifyVaultBalance` and `modifySubvaultBalance` are routine
  deposit, queue, push, and pull accounting paths. A per-call percentage cap rejects healthy large
  operations and can still be bypassed by splitting one change across calls.
- `MellowOracleReportGuardAssertion`: suspicious reports may be stored and accepted later. Once
  stored, `getReport` no longer exposes the previously accepted price, so a stateless acceptance
  check has no independent baseline. Blocking the suspicious submission instead would reject a
  supported protocol workflow.

Their helper functions remain as policy prototypes, but their old behavior tests are no longer
part of the executable semantic suite.

`MellowSubvaultAllocationAssertion` remains an opt-in deployment policy for one explicitly bound
Subvault, asset, and aToken pair. It compares position growth with reserve cash. This is a liquidity
threshold, not proof that the position can be withdrawn: reserve pause state, account health, and
external market mutations remain outside its observations. `priceD18` elsewhere in Mellow is
shares per asset, so asset value per share moves in the reciprocal direction.

All deployments must pin the Vault/Oracle/RiskManager/Subvault proxy implementations and exclude
the native-ETH sentinel from ERC-20 based assertions.
