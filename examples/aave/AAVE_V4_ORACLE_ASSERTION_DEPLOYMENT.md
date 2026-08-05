# Aave V4 consumed-oracle assertion deployment

`AaveV4EthereumMainSpokeOracleAssertion` is pinned to Ethereum Main Spoke state
at block 25,646,732 and Aave V4 release `v0.5.11`.

## Constructor

```solidity
new AaveV4EthereumMainSpokeOracleAssertion(
  maxTraceCalls,
  deviationBpsByReserveId,
  extraVerifiedConfigSlots
);
```

- `maxTraceCalls`: transaction-wide maximum for committed
  `getReservePrice` calls and configured-source `latestAnswer` calls. `64` is a
  practical initial value for the 14-reserve Main Spoke and two full price
  sweeps. Lower values reduce worst-case work but reject larger multicalls.
- `deviationBpsByReserveId`: 14 tolerances ordered by reserve ID:
  WETH, wstETH, weETH, WBTC, cbBTC, AAVE, LINK, USDC, USDT, EURC, RLUSD, USDG,
  frxUSD, GHO. Zero means exact equality with the PreTx price. A value of 100
  permits `[99%, 101%]`, with conservative rounding at both bounds.
- `extraVerifiedConfigSlots`: additional `(target, slot)` guards. The wrapper
  already includes all 22 verified mutable Chainlink/CAPO routing slots in the
  pinned source graph. Do not add guesses; document the upstream layout and
  deployed bytecode for every extra slot.

The constructor rejects a zero target, zero trace bound, more than 64 policies,
more than 128 total config guards, duplicate guards, duplicate direct sources,
non-contiguous reserve IDs, zero assets/sources, and tolerances at or above
10,000 bps.

## Adoption checklist

Before activation:

1. Confirm chain ID 1 and Main Spoke
   `0x94e7A5dCbE816e498b89aB752661904E2F56c485`.
2. Re-read the ERC-1967 implementation slot and require
   `0xABd0E26FE17BDe4F1f1187Ed8aA80C274E03D8b5`.
3. Require `ORACLE()` to equal
   `0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127`, oracle `spoke()` to point back
   to Main Spoke, and oracle decimals to equal 8.
4. Re-read all 14 reserves and direct sources and compare them with the
   production wrapper.
5. Review the source graph and built-in config slots against verified deployed
   source. Rebuild the wrapper after any upstream migration.
6. Choose asset-specific tolerances. Zero is appropriate only when legitimate
   within-transaction source movement is impossible or should be blocked.
7. Run the focused PCL suite with `-vvvv`; confirm parent/child call IDs and
   outputs are still exposed as documented.
8. Measure a worst-case multicall under the production executor. The current
   14-reserve/two-sweep fixture measures 2,881,782 gas.

At runtime, the assertion validates policy completeness and exact PreTx
reserve/source identity before accepting a committed price read. A legitimate
reserve addition, source update, proxy rotation, CAPO parameter update, or
Spoke upgrade intentionally blocks risk-sensitive operations until a reviewed
replacement assertion is deployed.

## Generic deployments

`AaveV4OracleConsumptionAssertion` can protect another verified V4 Spoke, but
the caller must provide:

- the exact Spoke adopter;
- the oracle selected by that implementation;
- the expected Spoke implementation;
- a complete reserve policy with unique direct sources; and
- verified storage guards for every mutable router, proxy, adapter, fallback,
  or provider slot that can change a consumed price.

Do not copy the Ethereum Main Spoke asset list, sources, implementation, or
storage guards to another Spoke or chain. See the accompanying
[research note](research/aave-v4-oracle-consumption-protection-2026-07-30.md)
for the exact source and trace evidence.
