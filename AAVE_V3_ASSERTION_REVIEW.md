# Adversarial review of the Aave V3 Credible Layer assertions

Date: 2026-07-30
Repository commit: `5f258a231b092120241e8d8ed629acd30c580f4c`
Review scope: Aave V3/Horizon only. Aave V4 files and conclusions are excluded.

> **Post-review remediation (2026-07-30):** The oracle-envelope findings below describe the
> implementation reviewed at repository commit `5f258a2`. That implementation has since been
> replaced in this workspace by a consumption-time trace guard. The replacement compares exact
> Pool-consumed AaveOracle returns with per-asset PreTx baselines, rejects source/fallback
> write-restore sequences, checks the Pool's actual provider return, includes the debt-opening
> `flashLoan` path, and fails closed on incomplete asset/trace configuration. The focused
> [`AaveV3HorizonOracleAssertion.t.sol`](examples/aave/test/AaveV3HorizonOracleAssertion.t.sol)
> suite passes 12/12 PCL tests. Two-asset stable borrow and two-borrow multicall costs are 186,556
> and 241,607 assertion gas; a temporary flash-loan callback manipulation trips at 211,875 gas.
> An isolated eight-asset probe used 586,471 gas, below the production executor's 3,000,000
> default but above the local PCL cheatcode's stricter 300,000 test threshold. The replacement
> still cannot establish that a price already corrupted before PreTx is correct; an independent
> reference remains complementary.

Evidence labels used below:

- **Verified from source** — established directly from pinned Aave or credible-std source/history.
- **Demonstrated by test** — reproduced with an isolated Foundry/PCL test or trace.
- **Supported inference** — conclusion follows from verified code, but was not reproduced against a live deployment.
- **Unverified hypothesis** — plausible, but needs additional evidence.

## 1. Overall verdict

None of the reviewed Aave V3 assertions should be kept as-is.

1. **Reserve backing — Rework.** The intended custody/liability invariant is consequential and not enforced by one local Aave `require`, but the current Pool-adopted transaction-end trigger does not run for the direct underlying-token mutations that its NatSpec claims to block. Its equation also omits the indexed, accrued treasury liability and uses one raw-unit tolerance for every reserve. **Demonstrated by test; verified from source.**
2. **Oracle envelope — Replace with a better invariant.** The intended protection is high-value, but the implementation compares only transaction endpoints. It misses a temporary oracle/provider/source installed for the exact Pool call and restored afterward, and a permanent provider switch to an already-existing oracle. A stable one-borrow/two-reserve case costs 325,294 assertion gas and exceeds the local PCL 300,000 limit; two borrows cost 600,747. **Demonstrated by test.**
3. **Aave V3-like operation safety — Remove from the advertised Horizon bundle in its current form.** The production wrapper constructs a child suite in assertion initcode, but that child has no runtime code in the PCL assertion execution environment. Every monitored call therefore fails before a selector can be registered or an invariant can be evaluated. Even if flattened, the health-factor and bounded-consumption checks mostly restate Aave v3.3 validation, and the aToken transfer health check uses the wrong pre-call boundary. **Demonstrated by test; verified from source.**

The reserve and oracle *ideas* are more security-interesting than the shared operation checks. Correctness is the gate, however: the two interesting ideas presently have complete same-transaction bypasses, while the operation bundle is not operational.

## 2. Complete Aave V3 surface inventory

| File/surface | Role | Review status |
|---|---|---|
| [`examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol) | Pool-adopted transaction-end reserve backing check | Reviewed in full |
| [`examples/aave/src/AaveV3HorizonOracleAssertion.sol`](examples/aave/src/AaveV3HorizonOracleAssertion.sol) | Pool-adopted transaction-end oracle/source envelope | Reviewed in full |
| [`examples/aave/src/AaveV3HorizonHelpers.sol`](examples/aave/src/AaveV3HorizonHelpers.sol) | Fork-aware Pool/provider/oracle readers, price comparison, bitmap helpers | Reviewed in full |
| [`examples/aave/src/AaveV3HorizonInterfaces.sol`](examples/aave/src/AaveV3HorizonInterfaces.sol) | Oracle, ERC-20 accounting, deficit interfaces | ABI-reviewed |
| [`src/protection/lending/examples/AaveV3PostOperationSolvency.sol`](src/protection/lending/examples/AaveV3PostOperationSolvency.sol) | Horizon suite/wrapper and compatibility aliases | Reviewed in full |
| [`src/protection/lending/examples/AaveV3LikeOperationSafety.sol`](src/protection/lending/examples/AaveV3LikeOperationSafety.sol) | Wrapper holding an external suite | Reviewed in full |
| [`src/protection/lending/examples/AaveV3LikeHelpers.sol`](src/protection/lending/examples/AaveV3LikeHelpers.sol) | Six-operation decoder, HF snapshots, withdrawal/liquidation consumption | Reviewed in full |
| [`src/protection/lending/examples/AaveV3LikeInterfaces.sol`](src/protection/lending/examples/AaveV3LikeInterfaces.sol) | Current shared Aave-like ABI and legacy reserve tuple | ABI-reviewed |
| [`src/protection/lending/examples/AaveV3Interfaces.sol`](src/protection/lending/examples/AaveV3Interfaces.sol) | Older duplicate Aave V3 interfaces | Unused by Solidity imports; ABI-reviewed |
| [`src/protection/lending/LendingBaseAssertion.sol`](src/protection/lending/LendingBaseAssertion.sol) | Per-call trigger, call resolution, consumption/HF enforcement | Reviewed in full |
| [`src/protection/lending/ILendingProtectionSuite.sol`](src/protection/lending/ILendingProtectionSuite.sol) | Common operation/snapshot/check types | Reviewed in full |
| [`test/protection/lending/AaveV3LikeOperationSafety.t.sol`](test/protection/lending/AaveV3LikeOperationSafety.t.sol) | Selector/decoder/deployment unit tests | Inventoried and run |
| [`test/protection/lending/LendingSolvencyPerCall.t.sol`](test/protection/lending/LendingSolvencyPerCall.t.sol) | Generic flat-suite PCL behavior | Inventoried and run |
| [`examples/aave/test/AaveV3AdversarialResearch.t.sol`](examples/aave/test/AaveV3AdversarialResearch.t.sol) | Isolated review harness for backing, oracle, trigger, gas, and child-suite behavior | Added for this review |
| [`examples/aave/test/AaveV3OperationBoundaryResearch.t.sol`](examples/aave/test/AaveV3OperationBoundaryResearch.t.sol) | Isolated aToken/finalizeTransfer call-boundary harness | Added for this review |

Repository search found no other active Aave V3 assertion implementation. The `examples/aave/test/` committed tests are V4-only. `AaveV3Interfaces.sol` is a stale duplicate and is not imported anywhere. Aave V4 contracts were kept separate and were not used to support any V3 conclusion. **Verified from source.**

## 3. Pinned upstream versions, audits, deployments, and provenance

### Protocol source

- Ordinary Aave comparison point: official [`aave-dao/aave-v3-origin` v3.3.0, commit `5431379f8beb4d7128c84a81ced3917d856efa84`](https://github.com/aave-dao/aave-v3-origin/tree/5431379f8beb4d7128c84a81ced3917d856efa84). The official [v3.3.0 release](https://github.com/aave-dao/aave-v3-origin/releases/tag/v3.3.0) identifies deficit accounting, v3.3 liquidation changes, and the legacy getter changes.
- Horizon comparison point: locally available official `aave/aave-v3-horizon`, remote `git@github.com:aave/aave-v3-horizon.git`, main commit [`6e2a51ea2e67af8aacf63f835d2e2b26dc7a2741`](https://github.com/aave/aave-v3-horizon/tree/6e2a51ea2e67af8aacf63f835d2e2b26dc7a2741), package version `3.3.0`.
- The ordinary v3.3 tag is the merge base of Horizon main. Between those pins, the reviewed Pool, `AaveOracle`, Pool libraries, and accounting types are unchanged; Horizon adds `RwaAToken`, `RwaATokenManager`, two errors, and two `AToken` visibility changes required for the RWA subclass. **Verified from source.**
- The exact Horizon commit used by the assertion author was not recorded. The assertion branch was created in April–May 2026; the official Horizon core at `6e2a51e` and the later docs branch `c1ec8c1` have no `src/contracts` differences. Using `6e2a51e` is therefore source-accurate for the reviewed interfaces and logic, but the missing original pin remains a provenance gap. **Verified from source; supported inference.**

Ordinary Aave v3.3 and Horizon therefore share the reserve, oracle, health-factor, withdraw, liquidation, eMode, flash-loan, and bitmap behavior assessed below. Horizon-specific differences are the permissioned RWA aToken restrictions: ordinary transfers, `transferOnLiquidation`, `transferUnderlyingTo`, and `mintToTreasury` revert, while `authorizedTransfer` is privileged and still routes through the normal validated aToken transfer path. See the pinned [`RwaAToken`](https://github.com/aave/aave-v3-horizon/blob/6e2a51ea2e67af8aacf63f835d2e2b26dc7a2741/src/contracts/protocol/tokenization/RwaAToken.sol). **Verified from source.**

### Horizon audits

- [Certora, `2025-05-30_Certora_Horizon-v3.3.0.pdf`](https://github.com/aave/aave-v3-horizon/blob/6e2a51ea2e67af8aacf63f835d2e2b26dc7a2741/audits/2025-05-30_Certora_Horizon-v3.3.0.pdf), SHA-256 `4829462e17fd1593f75cc13a59a170c29c154fa73c62945532564ac7b5a0d7d5`, reviewed commit `04419e25d3e87327487517bf0846ffa65aac35a2`.
- [StErMi, `2025-06-25_StErMi_Horizon-v3.3.0.pdf`](https://github.com/aave/aave-v3-horizon/blob/6e2a51ea2e67af8aacf63f835d2e2b26dc7a2741/audits/2025-06-25_StErMi_Horizon-v3.3.0.pdf), SHA-256 `1f63681f73e8399dd1906038051c89e1eafc051e81038d1cbead326a6aca907a`, initial commit `04419e25d3e87327487517bf0846ffa65aac35a2`, final fix commit `417a4768051126e14e492dd088c5b64add4a5b24`.

Both audits scope the Horizon RWA extension, not these Credible assertions. Certora confirms RWA underlying can move on withdraw/liquidation subject to the issuer token’s permissioning. StErMi calls out privileged `authorizedTransfer`, states that configured RWA reserves do not accrue aRWA treasury shares, and discusses coordinated liquidation creating v3.3 deficit. Those findings strengthen the relevance of cross-contract monitoring but do not validate the reviewed assertion equations or triggers. **Verified from primary audit artifacts.**

### Deployments

Official Horizon Ethereum constants at the pinned Horizon commit identify:

- PoolAddressesProvider: `0x5D39E06b825C1F2B80bf2756a73e28eFAA128ba0`
- Pool proxy: `0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8`
- AaveOracle: `0x985BcfAB7e0f4EF2606CC5b64FC1A16311880442`
- PoolConfigurator: `0x83Cb1B4af26EEf6463aC20AFbAC9c0e2E017202F`

Primary source: pinned [`AaveV3HorizonEthereum.sol`](https://github.com/aave/aave-v3-horizon/blob/6e2a51ea2e67af8aacf63f835d2e2b26dc7a2741/tests/horizon/utils/AaveV3HorizonEthereum.sol).

The historical local `aave` branch’s `assertions/credible-aave.toml` instead configured the operation wrapper on ordinary Aave V3 Base:

- Base Pool: `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5`
- Base provider: `0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D`

These addresses match the official Aave address book at pinned commit [`dd5a718d6739342882dd3327739dc037c4fd0028`](https://github.com/aave-dao/aave-address-book/blob/dd5a718d6739342882dd3327739dc037c4fd0028/src/AaveV3Base.sol). No repository evidence shows a Horizon assertion release configured against the Horizon Ethereum Pool. **Verified from source/history.**

## 4. ABI, struct, and token-semantics review

### Function selectors and return values

| Function | Selector | Upstream compatibility |
|---|---:|---|
| `borrow(address,uint256,uint256,uint16,address)` | `0xa415bcad` | Exact Horizon/v3.3 Pool ABI |
| `withdraw(address,uint256,address)` | `0x69328dec` | Exact; returns actual `uint256 amountToWithdraw` |
| `liquidationCall(address,address,address,uint256,bool)` | `0x00a718a9` | Exact |
| `setUserUseReserveAsCollateral(address,bool)` | `0x5a3b74b9` | Exact |
| `finalizeTransfer(address,address,address,uint256,uint256,uint256)` | `0xd5ed3933` | Exact |
| `setUserEMode(uint8)` | `0x28530a47` | Exact on Ethereum Pool; L2 compressed overload omitted |
| `getReserveData(address)` | `0x35ea6a75` | Exact legacy tuple in v3.3 |
| `getReserveDeficit(address)` | `0xc952485d` | Added in v3.3, not v3.6 |
| `getAssetPrice(address)` | `0xb3596f07` | Exact, returns `uint256` |
| `getSourceOfAsset(address)` | `0x92bf2be0` | Exact, returns `address` |
| `getFallbackOracle()` | `0x6210308c` | Exact, returns `address` |
| `getPriceOracle()` | `0xfca513a8` | Exact, returns `address` |

**Verified from source.**

### Reserve tuple

The local `AaveV3LikeTypes.ReserveData` field order and widths exactly match v3.3 `DataTypes.ReserveDataLegacy`: configuration word, five `uint128` indexes/rates, `uint40` timestamp, `uint16` id, four addresses, and three trailing `uint128` accounting fields. Encoding the single-member upstream `ReserveConfigurationMap` as local `uint256 configurationData` is ABI-equivalent. See the pinned [`DataTypes.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/types/DataTypes.sol). **Verified from source.**

Compatibility limits:

- v3.0/v3.1 used a real stable-debt token in this tuple.
- v3.2 removed stable borrowing but retained the legacy tuple. v3.3 fills `stableDebtTokenAddress` from provider key `MOCK_STABLE_DEBT`; that mock is expected to return zero. The backing assertion trusts any nonzero configured address’s `totalSupply()`, so a misconfigured or upgraded mock can create artificial backing.
- v3.3 stores deficit in the internal deprecated stable-rate slot and exposes it through the separate `getReserveDeficit` getter. The local interface comment claiming a “v3.6 accounting surface” is factually wrong.
- The reviewed tuple is correct for the pinned v3.3 release. Compatibility with a later release that changes/removes the legacy getter is not established by the code.

**Verified from source.**

### Accounting-token semantics

`AToken.totalSupply()` and `balanceOf()` are normalized, interest-bearing claims: scaled balances multiplied by the current normalized income. `VariableDebtToken.totalSupply()` is similarly normalized by the variable debt index. They are the right *realized* user-liability and debt quantities. `reserve.accruedToTreasury`, however, is a **scaled, not-yet-minted aToken liability**. On `mintToTreasury`, Aave computes:

`amountToMint = accruedToTreasury.rayMul(normalizedIncome)`

and mints that many aTokens. Aave’s own supply-cap validation includes scaled aToken supply plus `accruedToTreasury`, then applies the next liquidity index. See pinned [`PoolLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/PoolLogic.sol), [`ReserveLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/ReserveLogic.sol), and [`ValidationLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/ValidationLogic.sol). **Verified from source.**

## 5. Formal invariants and complete execution paths

### A. Reserve backing

#### Implemented invariant

For each constructor-configured reserve `r`, at `PostTx`:

`S_a(r) <= C(r) + D_s(r) + D_v(r) + U(r) + F(r) + ε`

where:

- `S_a`: normalized aToken `totalSupply`
- `C`: actual underlying ERC-20 balance held by the aToken
- `D_s`: stable-debt `totalSupply`, optional
- `D_v`: normalized variable-debt `totalSupply`
- `U`: `reserve.unbacked`
- `F`: `Pool.getReserveDeficit`
- `ε`: one constructor-wide raw `MAX_BACKING_DEFICIT`

The intended threat is external custody or accounting-token mutation that creates more redeemable aToken claims than cash, collectible debt, unbacked bridge accounting, or recognized bad debt. The exact implementation is at [`AaveV3HorizonReserveBackingAssertion.sol:35`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L35) and [`:70`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L70).

#### Correct economic equation

For a standard, non-rebasing asset, ignoring bounded rounding:

`S_a + (accruedToTreasury × normalizedIncome) = C + D_s + D_v + U + F`

`virtualUnderlyingBalance` is not an additional backing asset. It is Aave’s rate/utilization accounting balance and can diverge from actual custody after donations; redemption is still backed by the actual underlying held by the aToken. **Verified from source.**

Signs and special cases:

- Variable and stable debt are positive assets of the reserve.
- Unbacked is positive: `mintUnbacked` creates aTokens and matching unbacked; `backUnbacked` replaces unbacked with custody.
- Deficit is positive: v3.3 bad-debt liquidation burns unrecoverable variable debt and adds the same outstanding amount to deficit. `eliminateReserveDeficit` burns coverage aTokens (virtual accounting) or disposes underlying for the nonvirtual GHO special case while reducing deficit.
- Pending treasury accrual belongs on the liability side. Omitting it creates slack equal to the indexed pending treasury claim.
- RWA aTokens currently block `mintToTreasury`, and the audited deployment expects no aRWA treasury shares. The omission is still material for Horizon’s ordinary stablecoin/debt reserves, which use standard aTokens.
- A reserve without stable debt is valid. In v3.2+ the returned stable-debt field is zero or a zero-returning compatibility mock.

**Verified from source.**

The one-sided direction is reasonable *if* the policy is minimum backing: donations, positive rebases, and excess debt should not be rejected. Equality would create false positives. The safe one-sided form must still include every liability and should usually reject a **worsening deficit**, not freeze all future Pool traffic merely because old state is outside a hard endpoint bound. **Supported inference.**

#### Trigger and reachability

The assertion registers only `registerTxEndTrigger` and requires the adopter to equal `POOL`. A transaction touching only an underlying, aToken, debt token, oracle, or provider does not execute this Pool-adopted assertion. A direct custody seizure is detected only if the same transaction also successfully touches the Pool, or at a later Pool-touching transaction when it is too late to block the causing transaction. Reverted Pool calls do not select the trigger. **Demonstrated by test.**

The old `aave` branch test armed this assertion on the underlying collateral token and expected a direct seizure to trip. The later adopter-equality repair changed the valid adopter to the Pool, but the direct-movement NatSpec and trigger claim were not corrected and the behavioral V3 test was removed during example consolidation. **Verified from history.**

#### Assumptions

- The configured asset list exactly covers every live reserve and is updated on listings.
- Every asset is a conventional ERC-20 whose `balanceOf` and `totalSupply` are meaningful and non-reverting at fork snapshots.
- Underlying is not negative-rebasing and has no privileged balance rewrite that should be accepted.
- Transfers are not fee-on-transfer; token hooks/rebases cannot create an honest endpoint imbalance.
- Debt/aToken implementations and provider `MOCK_STABLE_DEBT` are trusted and ABI-compatible.
- A temporary intra-transaction deficit is not itself exploitable, because only `PostTx` is checked.
- `ε` is correctly chosen in each asset’s smallest units—an assumption contradicted by using one value for all assets.

### B. Oracle envelope

#### Implemented invariant

Let `O_post` be the oracle address read from the provider at `PostTx`. For each successful matching Pool call and each discovered active/touched asset `a`:

1. `source(O_post, a, PreTx) = source(O_post, a, PostTx)`
2. both endpoint prices are positive
3. the symmetric price ratio is within `ORACLE_DEVIATION_BPS`

The six enumerated call groups are `borrow`, `withdraw`, collateral toggle, `finalizeTransfer`, `setUserEMode`, and `liquidationCall`. The implementation is at [`AaveV3HorizonOracleAssertion.sol:50`](examples/aave/src/AaveV3HorizonOracleAssertion.sol#L50).

The account mapping is ABI-correct:

- borrow → `onBehalfOf`
- withdraw/collateral/eMode → immediate Pool caller
- finalizeTransfer → `from`
- liquidation → liquidated `user`

Touched assets are decoded correctly for every selector except eMode, which has no single touched asset and depends entirely on the user-position scan. `getAllCallInputs` returns argument tails without selectors; this assertion decodes the tails directly and is correct. The generic per-call base correctly prepends the selector before passing to its decoder. **Verified from source.**

#### Trigger, calls, and forks

- One Pool-adopted `TxEnd` trigger; provider/oracle/source-only transactions do not run it.
- PCL 1.6.0 returns only successful calls from `getAllCallInputs`. A trace with one successful and one caught/reverted `borrow` returned only the successful call. A transaction containing only a caught/reverted Pool call executed zero assertions.
- The reserve list and each reserve’s id come from `PostTx`, while both pre- and post-user bitmaps are interpreted with those post ids. Ordinary v3.3 never renumbers existing ids and only drops empty reserves, so this is safe under the current administrative logic. It is not robust against a buggy upgrade that changes ids—the class of failure an external assertion should ideally tolerate.
- All oracle reads use the single `O_post` address at both forks.

**Demonstrated by test; verified from source.**

#### Required assumptions

- Provider oracle identity is constant, or the post oracle is the oracle whose pre-state should be used.
- The price that mattered to the Pool equals one of the transaction endpoints.
- No source, fallback, proxy implementation, aggregator implementation, or answer is maliciously changed and restored inside the transaction.
- Every affected account is reachable through the six selected external selectors.
- Reserve count is at most `MAX_RESERVES_TO_SCAN`.
- Work remains below the assertion budget for arbitrary successful call multiplicity.
- One global percentage tolerance is operationally appropriate for stablecoins, NAV-based RWAs, and volatile collateral.

Several assumptions are false under the stated threat model.

### C. Aave V3-like operation safety

For each **successful** monitored Pool frame `c`:

1. If the decoded operation increases debt, reduces effective collateral, or changes eMode, and the selected account is solvent at `PreCall(c)`, require it is solvent at `PostCall(c)`:

   `debt_post = 0 OR healthFactor_post >= 1e18`

2. For withdrawal:

   `abi.decode(callOutput(c)) <= aToken.balanceOf(caller, PreCall(c))`

3. For liquidation:

   `debtAsset transferred(liquidator → debt aToken, c) <= stableDebt(user, pre) + variableDebt(user, pre)`

   `collateral transferred(to liquidator, c) <= aToken.balanceOf(user, pre)`

The base resolves the exact call through trigger context and call id, uses `PreCall`/`PostCall`, and subtracts cumulative ERC-20 transfer observations to isolate one call window. Multiple successful matching calls each get their own execution. **Verified from source; demonstrated by generic test.**

Deployment assumptions fail: [`AaveV3PostOperationSolvency.sol:29`](src/protection/lending/examples/AaveV3PostOperationSolvency.sol#L29) creates `AaveV3HorizonProtectionSuite` in constructor initcode and stores its address. In the PCL assertion runtime that child has no code. The historical behavioral test explicitly documented this and substituted a flat fixture; the production wrapper itself had no positive E2E. **Verified from history; demonstrated by test.**

## 6. Scorecard and dispositions

Scores are 0–5. “Correctness” is shipping correctness, including operational reachability; it is not a score for the idea in isolation.

| Assertion/check | Protected threat | Trigger and reachability | Correctness | Security interest | Redundancy with Aave | Principal false positive | Principal false negative/bypass | Evidence strength | Disposition |
|---|---|---|---:|---:|---|---|---|---|---|
| Reserve backing | External custody loss, bad accounting-token mint, upgrade/accounting bug | Pool-adopted TxEnd; only successful Pool-touching transactions | 2/5 | 4/5 | No single equivalent cross-contract postcondition | Old/unmodeled deficit, fee/rebase token behavior, raw tolerance mismatch | Direct token-only mutation; temporary deficit restored; pending treasury masks loss | Strong source + PCL mocks; no live fork | **Rework** |
| Oracle envelope | Oracle/source manipulation coupled to risk action | Pool-adopted TxEnd; six successful selector groups | 1/5 | 4/5 | Aave access control and Horizon DON bounds exist, but no same-tx cross-contract envelope | Honest price move over tolerance; new oracle not present at PreTx; OOG | Temporary manipulation/restore; permanent provider switch; omitted flash-loan debt path | Strong source + PCL mocks/traces; no live fork | **Replace with a better invariant** |
| Post-operation HF | Buggy Pool leaves healthy user liquidatable | Per-call on six selectors, but production child suite is unavailable | 1/5 | 2/5 | Borrow/withdraw/disable/transfer/eMode already validate HF/LTV | Current bundle reverts before evaluation; if flattened, oracle update can alter HF | aToken balance mutation precedes `finalizeTransfer` PreCall; flash-loan debt path omitted | Strong for operational failure/boundary; no real Aave fork | **Remove current wrapper; rework only if retained as defense in depth** |
| Withdrawal claim bound | Pool returns more underlying than caller claim | Same unusable wrapper; per-withdraw call if flattened | 1/5 | 1/5 | Exact `amount <= userBalance`, max sentinel clipping, then burn | Current bundle operational failure | A malicious transfer without standard event semantics; otherwise check is redundant | Source-strong, no Aave behavioral E2E | **Remove** |
| Liquidation debt bound | Liquidator repays more than user debt | Same unusable wrapper; per-liquidation call if flattened | 1/5 | 1/5 | v3.3 clips to user debt/close factor/collateral | Current bundle operational failure | Does not prove debt burned equals assets received or deficit created correctly | Source-strong, no Aave behavioral E2E | **Replace with settlement identity** |
| Liquidation collateral bound | Liquidator receives more than user collateral | Same unusable wrapper; per-liquidation call if flattened | 1/5 | 1/5 | v3.3 caps collateral by user balance | Current bundle operational failure | Counts only liquidator leg, omitting protocol-fee transfer from user | Source-strong, no Aave behavioral E2E | **Replace with settlement identity** |

Dimension detail:

| Surface | Model accuracy | ABI/accounting | Trigger reachability | Bypass resistance | FP safety |
|---|---:|---:|---:|---:|---:|
| Reserve backing | 2 | 4 | 1 | 1 | 2 |
| Oracle envelope | 2 | 4 | 3 | 0 | 1 |
| Operation HF | 4 | 4 | 0 | 1 | 0 |
| Withdraw bound | 4 | 4 | 0 | 2 | 0 |
| Liquidation debt bound | 3 | 4 | 0 | 2 | 0 |
| Liquidation collateral bound | 2 | 4 | 0 | 1 | 0 |

## 7. Detailed findings ordered by severity

### Critical — production operation wrapper cannot execute its suite

**Demonstrated by test.** The production wrapper constructs and stores the child at [`AaveV3PostOperationSolvency.sol:29`](src/protection/lending/examples/AaveV3PostOperationSolvency.sol#L29). Its `_suite().getMonitoredSelectors()` and later suite calls target that address, which has no code in assertion execution. `pcl test -vvvv` shows the external child call stop with empty return data and the wrapper revert with empty data. The repository’s removed `AaveV3OperationSafetyBehavior.t.sol` already acknowledged the limitation and tested a flat substitute instead.

Impact: the advertised bundle provides none of its six protections and can reject monitored Pool traffic operationally. Compilation and direct EVM deployment tests do not detect this execution-model failure.

### High — backing assertion does not fire for its claimed threat

**Demonstrated by test.** A direct `underlying.seize(aToken, recipient, amount)` after arming the assertion on the Pool executes zero assertions. Adding a successful Pool call to the same transaction causes the same deficit to trip. The contradictory NatSpec is at [`AaveV3HorizonReserveBackingAssertion.sol:12`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L12) and [`:31`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L31).

This is not delayed detection equivalent to transaction blocking: the causing transfer commits, and the next unrelated Pool user may be the transaction rejected.

### High — endpoint oracle comparison misses the price actually consumed

**Demonstrated by test.** The assertion resolves only the post-state oracle at [`AaveV3HorizonOracleAssertion.sol:53`](examples/aave/src/AaveV3HorizonOracleAssertion.sol#L53), then supplies that one address to endpoint comparisons. The following sequences reach semantic completion without an oracle/source violation, then fail only because the assertion exceeds PCL’s gas budget:

- price `P → malicious P' → Pool.borrow → P`
- source `S → malicious S' → Pool.borrow → S`
- provider oracle `O → malicious O' → Pool.borrow → O`
- permanent provider change `O → existing O'`, with `O'` stable at both endpoints

The same construction applies to withdrawal, collateral disable, eMode, aToken transfer finalization, and liquidation. A healthy account can be made liquidatable only at the call’s manipulated price, liquidated, and the price restored before `PostTx`; endpoint equality does not reveal what `LiquidationLogic` consumed. Aave resolves the provider oracle inside each operation and reads asset prices during validation/liquidation; see pinned [`Pool.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/pool/Pool.sol) and [`LiquidationLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/LiquidationLogic.sol). **Verified from source.**

Persistent source changes are caught. Persistent price changes outside the configured band are caught. These positive cases do not repair the intermediate-value bypass.

### High — oracle cost is unbounded in calls and operationally over budget

**Demonstrated by test.**

- Two reserves, one stable borrow: 325,294 assertion gas; local limit 300,000.
- Two reserves, two stable borrows: 600,747.
- Persistent drift fails early at 260,079, so malicious tests can pass while the honest full-scan path OOGs.

Cost scales with six trace queries at [`AaveV3HorizonOracleAssertion.sol:57`](examples/aave/src/AaveV3HorizonOracleAssertion.sol#L57), matching-call count at [`:71`](examples/aave/src/AaveV3HorizonOracleAssertion.sol#L71), reserve count per affected account, and active/touched assets. Users/assets are not deduplicated. `MAX_RESERVES_TO_SCAN` bounds reserve count but not calls. The July 2026 backing-history commit records a production sidecar default of 3 million gas; that larger limit postpones, but does not remove, the multi-call denial boundary. A realistic eleven-reserve market and attacker-controlled successful batching were not measured against a live sidecar. **Supported inference.**

### High — reserve equation omits a real liability

**Verified from source; demonstrated by test.** The implemented sum at [`AaveV3HorizonReserveBackingAssertion.sol:78`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L78) never reads `accruedToTreasury`. A mock state with `aTokenSupply = cash` and positive accrued treasury passes, although minting the pending treasury claim would create an immediate shortfall. Interest accrual creates exactly this pending claim: variable debt grows by total interest, user aToken supply grows by the depositor share, and the reserve-factor share accumulates scaled in `accruedToTreasury`.

For current Horizon RWA aTokens the field should remain zero because `mintToTreasury` is blocked; stablecoin/debt reserves remain affected.

### Medium — `finalizeTransfer` PreCall is after the risky balance mutation

**Verified from source; demonstrated by test.** `AToken._transfer` executes `super._transfer` before `POOL.finalizeTransfer`. Consequently, `PreCall(finalizeTransfer)` already contains the reduced collateral balance. The base sees an already-insolvent account and intentionally returns at [`LendingBaseAssertion.sol:209`](src/protection/lending/LendingBaseAssertion.sol#L209). A control mutation performed *inside* `finalizeTransfer` is caught; the Aave-ordered mutation before it is skipped.

Aave’s own `finalizeTransfer` validation still protects real v3.3. This is a false negative specifically as independent defense against a buggy/modified Aave validation path, including Horizon’s privileged `authorizedTransfer`.

### Medium — operation safety mostly restates Aave v3.3

**Verified from source.** The local adapter’s six-selector list and HF selection are at [`AaveV3LikeHelpers.sol:63`](src/protection/lending/examples/AaveV3LikeHelpers.sol#L63) and [`:223`](src/protection/lending/examples/AaveV3LikeHelpers.sol#L223).

- Borrow requires pre-borrow HF `> 1e18` and then verifies total collateral can cover existing plus new debt at current LTV. This is stricter than merely checking post-HF `>= 1e18`.
- Withdraw clips `type(uint256).max` to the normalized user balance, requires amount `<= userBalance`, burns that amount, then validates HF/LTV when collateral supports debt.
- Disabling collateral changes the flag then validates HF/LTV.
- aToken transfer mutates balances then `finalizeTransfer` validates HF/LTV.
- eMode stores the new category then validates HF.
- Liquidation validation requires HF below one and v3.3 settlement clips debt and collateral using close factor, user debt, collateral, bonus, protocol fee, and dust rules.

Primary source: pinned [`ValidationLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/ValidationLogic.sol), [`SupplyLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/SupplyLogic.sol), and [`EModeLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/EModeLogic.sol).

The checks are defense in depth against an implementation upgrade or integration side effect, not new protections against ordinary Aave behavior. Because they trust `Pool.getUserAccountData`, a coherently buggy Pool risk view can also make both protocol validation and assertion agree on the same wrong result.

### Medium — selector coverage omits debt opened through `flashLoan`

**Verified from source.** Multi-asset `flashLoan` allows a non-`NONE` interest-rate mode. If funds are not returned, `FlashLoanLogic` calls `BorrowLogic.executeBorrow` internally and opens debt for `onBehalfOf`; there is no external Pool `borrow` selector frame. The local selector list at [`AaveV3LikeHelpers.sol:63`](src/protection/lending/examples/AaveV3LikeHelpers.sol#L63) and the oracle groups at [`AaveV3HorizonOracleAssertion.sol:57`](examples/aave/src/AaveV3HorizonOracleAssertion.sol#L57) both omit `flashLoan`. See pinned [`FlashLoanLogic.sol`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/FlashLoanLogic.sol).

Other omissions:

- Supply and repay are safely omitted from account HF because they are risk-improving under standard token behavior; they still matter to reserve-wide accounting.
- `flashLoanSimple` must be repaid and does not open debt, so omitting it from user HF is reasonable; it can still affect treasury/backing.
- mint/back-unbacked are reserve-wide, not account-HF operations.
- Ethereum Horizon uses the normal Pool ABI. The generic “Aave-like” claim does not cover L2Pool compressed borrow/withdraw/collateral selectors.
- Administrative configuration, proxy upgrades, provider/oracle changes, and direct token operations are outside the six selectors.

### Medium — one raw backing tolerance is not cross-asset safe

**Verified from source.** `MAX_BACKING_DEFICIT` is added directly to every reserve’s raw token amount at [`AaveV3HorizonReserveBackingAssertion.sol:87`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L87). A value of `1_000_000` is one whole USDC but only `10^-12` tokens for an 18-decimal reserve. Equal raw values do not represent equal rounding budgets or economic risk. A zero value may create rounding false positives; a value suitable for an 18-decimal asset may authorize material loss for a 6-decimal asset.

Use an immutable per-asset raw tolerance after deriving worst-case index/rounding error, or normalize into base value with a second trusted price source. The latter must not reuse the oracle being monitored without acknowledging circularity.

### Medium — liquidation collateral bound omits the protocol-fee leg

**Verified from source.** The local calculation at [`AaveV3LikeHelpers.sol:423`](src/protection/lending/examples/AaveV3LikeHelpers.sol#L423) counts only collateral sent to the liquidator:

- receive-aToken: user aToken → liquidator
- receive-underlying: underlying aToken → liquidator

v3.3 separately transfers `liquidationProtocolFeeAmount` in aTokens from the user to the treasury. Therefore the assertion does not bound the user’s total collateral debit. Horizon RWA liquidation requires the protocol fee to be configured to zero because `RwaAToken.transferOnLiquidation` reverts, but ordinary stable/crypto collateral can have a fee. The current inequality is also much weaker than an exact settlement reconciliation.

### Medium — oracle false positives and configuration gaps

**Demonstrated by test; verified from source.** The global endpoint comparison is implemented at [`AaveV3HorizonHelpers.sol:67`](examples/aave/src/AaveV3HorizonHelpers.sol#L67), and constructor configuration is accepted without a Pool/provider relationship check at [`AaveV3HorizonOracleAssertion.sol:25`](examples/aave/src/AaveV3HorizonOracleAssertion.sol#L25).

- A legitimate 2% feed update bundled with a Pool borrow trips a 1% tolerance.
- Normal feed rounds can change while an unrelated account uses the Pool; the assertion does not establish causality between the update and malicious risk.
- Fallback-oracle identity is never compared. A fallback change is invisible whenever the primary remains positive, or whenever endpoint price remains within tolerance.
- Aggregator proxy implementation changes are invisible if the Aave source address and endpoint answer remain stable.
- A newly deployed post oracle may not exist at `PreTx`; reading the post address on the pre fork then fails.
- The provider passed to the constructor is not checked against `Pool.ADDRESSES_PROVIDER`, so a deployment can silently monitor the wrong provider.
- A static `MAX_RESERVES_TO_SCAN` becomes a market-wide denial if listings exceed it.

### Low — reserve-list lifecycle is manual

**Verified from source.** The backing assertion’s reserve array is constructor-supplied at [`AaveV3HorizonReserveBackingAssertion.sol:22`](examples/aave/src/AaveV3HorizonReserveBackingAssertion.sol#L22). New listings are not covered; stale dropped entries cause `"reserve not listed"` on every later Pool-touching transaction. The oracle assertion dynamically reads the post list, but with a hard maximum.

## 8. Operation-specific analysis

### Withdrawals

`type(uint256).max` is normalized by Aave to the current indexed user balance; `withdraw` returns the actual amount and the assertion decodes that output. `aToken.balanceOf` at `PreCall` calculates normalized income for the same block timestamp that `reserve.updateState` uses, so interest accrual should not create a meaningful mismatch beyond Aave’s own ray rounding. Partial/full paths are semantically handled. Multiple withdrawals are isolated by per-call forks. **Verified from source; generic per-call behavior demonstrated by test.**

Conclusion: logically accurate but almost perfectly redundant with `validateWithdraw`, and unusable in the production wrapper.

### Liquidations

- `type(uint256).max`/oversized `debtToCover` is clipped to maximum liquidatable debt.
- Partial/full close-factor behavior, available collateral, liquidation bonus, v3.3 dust thresholds, and deficit realization are implemented upstream before transfers.
- Debt bound observes actual debt-asset transfer, not requested calldata, and compares to normalized pre-call stable+variable debt.
- receive-aToken mode and receive-underlying mode select the correct liquidator transfer token/sender.
- The separate treasury protocol-fee collateral transfer is omitted.
- Exact correctness would reconcile debt burned, debt asset received, collateral debited, liquidator proceeds, treasury fee, user flags, and any deficit created. The current pair of upper bounds cannot catch under-burning debt, wrong-recipient transfer, wrong deficit, or a user debit hidden in another transfer leg.

**Verified from source.**

## 9. Test and infrastructure results

Toolchain:

- `pcl 1.6.0`, commit `4a134645d475`
- Forge `1.5.1`, commit `b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2`

### Commands and exact outcomes

```text
FOUNDRY_PROFILE=aave forge build
```

Pass. This proves compilation only.

```text
FOUNDRY_PROFILE=aave forge build --sizes
```

Pass. Deployed/init sizes were: operation wrapper 8,473/27,660 bytes, child suite 17,593 deployed bytes, oracle 9,664 deployed bytes, and reserve backing 5,290 deployed bytes. This rules out EVM bytecode-size rejection as the child-suite cause; it does not prove PCL runtime availability or execution gas safety.

```text
pcl test --match-contract AaveV3LikeOperationSafetyTest -vv
```

8/8 pass. They prove six selector values, caller/on-behalf decoding for unit fixtures, and suite deployment. They do not arm the production assertion, read Aave state, test bounds, or exercise trigger reachability.

```text
pcl test --match-contract LendingSolvencyPerCallTest -vv
```

6/6 pass. The flat generic suite proves honest/broken/pre-insolvent behavior, per-call transient break-then-repair detection, selector prepending, and legacy entrypoint semantics. It does not prove the production Aave adapter or child wrapper.

```text
forge test --offline --match-path 'test/protection/lending/*.t.sol' -vv
```

8 decoder/deployment tests pass; all 6 Credible E2Es fail on ordinary Forge’s unknown Credible cheatcode. PCL, not Forge, is the behavioral runner.

```text
FOUNDRY_PROFILE=aave pcl test --match-contract AaveV3OperationBoundaryResearchTest -vvvv
```

2/2 pass:

- mutation inside `finalizeTransfer` trips
- mutation before entry, matching aToken ordering, is skipped and leaves health `-1`

```text
FOUNDRY_PROFILE=aave pcl test --match-contract AaveV3AdversarialResearchTest -vv
```

Final run: 17 tests, 9 pass/8 fail as evidence. The nonzero exit is intentional: several research cases encode the expected assertion execution or gas outcome, so a PCL framework failure is the demonstrated defect:

- backing honest, deficit sign, same-tx Pool-touch seizure, treasury omission, and temporary restore behaviors reproduced
- direct token-only seizure fails because zero assertions execute
- persistent and legitimate oracle drift trip
- stable/full oracle paths exceed the 300,000 limit
- caught/reverted-only Pool call executes zero assertions
- production child suite reverts with empty data, as expected by the test
- with one successful and one caught/reverted borrow, `getAllCallInputs` returns exactly the successful call

The cardinality result was also isolated with a focused trace:

```text
FOUNDRY_PROFILE=aave pcl test \
  --match-test testGetAllCallInputsExcludesCaughtRevertedBorrow -vvvv
```

Pass. With one successful and one caught/reverted borrow, `getAllCallInputs` returns exactly the successful call.

### Mutation matrix

| Mutation | Intended result | Observed |
|---|---|---|
| Honest backing + Pool call | Pass | Pass, 169,918 assertion gas |
| Direct underlying seizure only | Trip | Zero assertion executions |
| Same seizure + Pool call | Trip | Trips |
| Add recognized v3.3 deficit equal to custody loss | Pass | Pass |
| Add pending treasury claim without backing | Trip under correct model | Pass |
| Seize, call Pool, restore before PostTx | Trip if intermediate forbidden | Pass |
| Persistent price/source drift | Trip | Trips before full scan |
| Temporary price/source/provider manipulation + restore | Trip | No semantic violation; then PCL OOG |
| Permanent provider switch to existing oracle | Trip | No semantic violation; then PCL OOG |
| Honest stable borrow | Pass | PCL OOG at 325,294 |
| Two honest borrows | Pass | PCL OOG at 600,747 |
| Ordinary 2% price update with 1% band | Operationally likely pass | Trips |
| Health break inside monitored call | Trip | Trips |
| aToken-ordered break before `finalizeTransfer` | Trip | Passes/skips |
| Production operation wrapper | Register and run | Empty child-suite revert |

### Fork/backtest status

No historical or live-fork results are claimed.

- No RPC/fork URL was present in the environment.
- `pcl doctor` reported `api_health: error` and `auth_capabilities: error` for `https://ethereum.phylax.systems/`.
- The repository contains official deployment addresses but no local archive RPC or cached Horizon transaction corpus.

Evidence that would resolve this gap: a pinned archive RPC, confirmed block ranges for Horizon Ethereum, the deployed assertion release/configuration and gas budget, and representative successful borrow/withdraw/liquidation/governance transactions. Required backtests should include oracle round-update bundles, every live reserve’s decimals/configuration, multi-call routers, deficit-creation liquidations, and authorized RWA transfers.

## 10. Unsupported or overstated comments

1. Reserve NatSpec says transaction-end runs “including direct reserve token movements outside the Pool call surface.” It does not when adopted by the Pool. **Demonstrated by test.**
2. Reserve notice says it protects against external underlying-token balance changes. It detects them only on a successful Pool-touching transaction, potentially later. **Demonstrated by test.**
3. Oracle NatSpec says it catches source swaps “earlier or later in the same transaction.” It catches only endpoint-persistent swaps, not swap/use/restore. **Demonstrated by test.**
4. Oracle notice says it protects the risk state consumed by the Pool. It never samples the oracle at the matching call boundary, so endpoint equality is not proof about the consumed value. **Verified from source; demonstrated by test.**
5. Operation wrapper says a revert means a risk-increasing Pool call violated a safety property. In the PCL runtime it can mean the constructor-created suite has no code. **Demonstrated by test.**
6. Operation helpers say the checks protect against over-liquidation. The collateral check omits the treasury fee leg and both checks are only upper bounds, not settlement correctness. **Verified from source.**
7. Horizon deficit interface says `getReserveDeficit` was added in v3.6. It was added in v3.3. **Verified from official release/source.**
8. The shared suite says it targets close forks generically. Its ABI omits L2 compressed entrypoints and assumes the v3 legacy reserve tuple/provider mock conventions. **Verified from source.**

## 11. Three materially higher-value missing assertions

### 1. Call-boundary oracle consumption/configuration invariant

For every successful risk operation, compare the provider/oracle/source/fallback identities at `PreTx`, `PreCall`, `PostCall`, and `PostTx`; sample the prices at `PreCall` (the value the Pool is about to consume) and bind them to an independent reference or asset-specific policy. Add triggers on provider/oracle configuration writes so oracle-only changes are not invisible. Cover flash-loan debt conversion and liquidation explicitly.

This is materially better because it detects temporary manipulation used by a real operation rather than merely endpoint drift. It must define governance allowlists and normal feed-update policy to avoid becoming a blanket oracle-change ban.

### 2. Exact reserve liability/custody no-worsening invariant

Per reserve:

`liability = aTokenSupply + accruedToTreasury × normalizedIncome`

`recognizedBacking = actualCustody + stableDebt + variableDebt + unbacked + deficit`

Reject any increase in `max(liability - recognizedBacking, 0)` beyond per-asset rounding tolerance. Register ERC-20 change triggers for each underlying and appropriate a/debt-token or storage changes, rather than relying only on Pool TxEnd. Separately reconcile virtual underlying accounting where enabled.

This preserves donation tolerance, includes treasury claims, tolerates pre-existing bad state without letting it worsen, and runs on the transaction that changes custody.

### 3. Exact liquidation settlement and deficit reconciliation

For each liquidation, reconcile:

- variable/stable debt reduction
- debt asset actually received
- collateral aToken debit
- underlying or aToken delivered to liquidator
- protocol fee delivered to treasury
- collateral/borrowing bitmap transitions
- v3.3 bad debt burned and deficit created

This detects wrong-recipient transfers, fee mistakes, under/over-burning, and bad deficit accounting that the current upper bounds and Aave’s local validation do not independently prove.

## 12. Prioritized remediation plan

1. **Quarantine the production operation wrapper immediately.** Do not advertise or deploy the child-suite form. Flatten suite and assertion into one runtime if any generic checks are retained, then require a real PCL E2E for every monitored selector.
2. **Fix trigger truth before equation work.** Redesign reserve triggers around underlying/aToken/debt-token changes and Pool accounting changes; explicitly test token-only transactions, reverted Pool calls, nested calls, and subsequent-detection behavior.
3. **Replace the reserve formula.** Include indexed `accruedToTreasury`, use per-asset tolerances, and prefer no-worsening deficit semantics. State unsupported token classes.
4. **Replace endpoint oracle logic with call-boundary logic.** Pin provider consistency, source/fallback/proxy identity policy, actual PreCall price, flash-loan debt path, and asset-specific tolerances. Deduplicate accounts/assets and strictly bound calls.
5. **Remove redundant bounds unless upgraded to exact reconciliation.** Withdrawal claim adds little beyond `validateWithdraw`. Replace liquidation upper bounds with full settlement/deficit identity.
6. **Add deployment validation.** Assert constructor provider equals `Pool.ADDRESSES_PROVIDER`, reserve list/count matches live configuration, every stable-debt compatibility address has the expected ABI/zero behavior, and configured gas budget covers worst-case measured paths.
7. **Restore behavioral V3 CI.** Keep the adversarial cases from the research harness, add a pinned Horizon fork, and fail CI if production assertion bytecode—not a flat substitute—cannot register and execute.
8. **Run historical backtests before disposition can improve to Keep.** Measure false positives over representative Horizon and ordinary Aave v3.3 transactions, including governance/source updates and realistic multi-call routers.

## 13. Remaining uncertainties

- **Unverified hypothesis:** whether the production sidecar’s actual assertion/precompile budgets and deployment compiler settings differ from the 3 million default recorded in repository history.
- **Unverified hypothesis:** whether any reviewed assertion is currently deployed or active on Horizon; no release manifest was found.
- **Unverified hypothesis:** live Horizon reserve count/configuration and `MOCK_STABLE_DEBT` behavior at a chosen historical block; no RPC was available.
- **Unverified hypothesis:** historical false-positive rates for normal RWA NAV updates, governance bundles, and oracle feed rounds.
- **Supported inference:** nonstandard RWA issuer token administration makes direct custody mutation a plausible high-impact failure, but the exact administrative capabilities differ by underlying asset and need token-by-token source review.
- **Supported inference:** an attacker can force oracle assertion OOG below a 3 million budget with enough successful calls; the exact minimum on the live eleven-reserve market needs a fork benchmark.

Until those gaps are closed, the evidence supports **Rework/Replace/Remove**, not “Keep, but strengthen tests.”
