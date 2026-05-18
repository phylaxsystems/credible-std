# Credible Assertion Patterns

Readable v2 examples distilled from the protocol branches in this repo. These are not precompile demos; each file shows one recurring protection pattern with the minimum scaffolding needed to make the assertion concrete.

Build:

```bash
FOUNDRY_PROFILE=micro-patterns forge build
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
