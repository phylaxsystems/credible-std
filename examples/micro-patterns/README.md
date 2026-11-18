# Credible Assertion Patterns

Run commands from the repository root after the [shared setup](../README.md#setup-and-checks).

Small examples of seven recurring assertion policies using simplified protocol interfaces.
These sketches explain mechanics; their assumptions must be adapted to the target protocol.

Build and run the participant-gate regression suite:

```bash
FOUNDRY_PROFILE=micro-patterns forge build
FOUNDRY_PROFILE=micro-patterns pcl test
```

| Pattern | Example | Distilled from |
| --- | --- | --- |
| Tiered circuit breaker | `src/TieredCircuitBreaker.a.sol` | Symbiotic vault, Euler EVault, Royco kernel, Spark SLL, Cap redemption gate |
| Accounting conservation | `src/AccountingConservation.a.sol` | Royco NAV, Aerodrome reserves, Curve custody/admin balances, Symbiotic total stake |
| Call-sandwich honesty | `src/CallSandwichHonesty.a.sol` | Euler ERC4626 preview/return/log checks, Symbiotic deposit/claim flow |
| Post-operation solvency | `src/PostOperationSolvency.a.sol` | Aave/Spark/Euler/Curve lending and perpetual operation-safety checks |
| Oracle reduce-only gate | `src/OracleReduceOnlyGate.a.sol` | SparkLend oracle guard, Curve oracle bounds, lending risk-increasing selector gates |
| Configuration guard | `src/ConfigurationGuard.a.sol` | Symbiotic vault config, access-control slot/share-price guards |
| Participant gate | `src/ParticipantGate.a.sol` | Cap OFAC participant screening and selector-specific address extraction |

## Scope and assumptions

Only `ParticipantGateAssertion` currently has dedicated runtime tests in this profile.
The remaining six patterns compile but have no dedicated behavior tests.

- **Accounting:** idle and invested assets must be disjoint; liabilities must exclude
  the separately counted pending withdrawals.
- **Call sandwich:** the mock interface assumes exact preview/return equality and
  one deposit event. It does not prove that assets moved or shares were minted.
- **Solvency:** the policy requires liquidation to restore full health. Protocols
  permitting partial liquidation need a different, protocol-specific condition.
- **Oracle gate:** only calls whose asset argument is the watched asset are checked.
  This does not cover borrowing another asset against mispriced collateral; both
  price feeds must also use matching denominations and precision.
- **Configuration:** mandatory manager/slasher wiring and the timing constants are
  example operator choices, not universal vault requirements.
- **Tiered breaker:** finding a liquidation in the same transaction does not prove
  it caused the outflow. The sketch needs causal attribution before deployment;
  the executor's rolling-window trigger is not exercised by this profile.
- **Participant gate:** queries the configured oracle at the pre-call snapshot and
  screens the transaction sender, immediate caller, and selector-specific parties.
  Its bounded caller lookup can reject transactions with more than 16 matching calls.
