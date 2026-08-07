# Aave V4 consumed-oracle-price protection

Research date: 2026-07-30<br>
Chain: Ethereum mainnet (chain ID 1)<br>
State pin: block 25,646,732<br>
Upstream release: `v0.5.11`<br>
Upstream commit: `cdacec509e4f848bff1a5556f503afa83eee3b79`

## Deployment and source pin

This implementation protects the Ethereum Main Spoke, not an inferred Aave V3
deployment:

| Component | Address |
| --- | --- |
| Main Spoke proxy | `0x94e7A5dCbE816e498b89aB752661904E2F56c485` |
| Main Spoke implementation | `0xABd0E26FE17BDe4F1f1187Ed8aA80C274E03D8b5` |
| Main Spoke `AaveOracle` | `0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127` |

The implementation was resolved from the ERC-1967 implementation slot at the
state pin. Sourcify reports a full runtime match. A local build of Aave V4 tag
`v0.5.11` used Solidity 0.8.28, optimizer 750, IR compilation, Cancun EVM, and
`bytecodeHash = none`; its compiler metadata tail matches the deployed
implementation and oracle. The official Aave address book was inspected at
commit `4ae19b95f84b077c28633ca1d0f9a6750a3ea1d4`, and its Aave V4 submodule
resolves the same release family.

Primary references:

- [Aave V4 `v0.5.11` source](https://github.com/aave/aave-v4/tree/cdacec509e4f848bff1a5556f503afa83eee3b79)
- [Pinned `AaveOracle.sol`](https://github.com/aave/aave-v4/blob/cdacec509e4f848bff1a5556f503afa83eee3b79/src/spoke/AaveOracle.sol)
- [Pinned `Spoke.sol`](https://github.com/aave/aave-v4/blob/cdacec509e4f848bff1a5556f503afa83eee3b79/src/spoke/Spoke.sol)
- [Pinned liquidation logic](https://github.com/aave/aave-v4/blob/cdacec509e4f848bff1a5556f503afa83eee3b79/src/spoke/libraries/LiquidationLogic.sol)
- [Official Ethereum address book](https://github.com/bgd-labs/aave-address-book/blob/main/src/AaveV4Ethereum.sol)
- [Aave V4 Ethereum activation](https://governance.aave.com/t/arfc-aave-v4-activation-on-ethereum-mainnet/24293)
- [Aave V4 live announcement](https://aave.com/blog/aave-v4-live-ethereum)

## Exact oracle architecture

The V4 Main Spoke has an immutable `ORACLE`; it does not discover a V3-style
provider at runtime. Its oracle is spoke-specific because reserve IDs, rather
than asset addresses, key the source mapping.

`AaveOracle` has:

- immutable `DECIMALS`, equal to 8;
- `address public spoke` in storage slot 0;
- `mapping(uint256 => IPriceFeed) _sources` in storage slot 1;
- `getReservePrice(uint256)`, which calls exactly
  `IPriceFeed(source).latestAnswer()`, rejects a missing source and every
  non-positive answer, and casts the positive `int256` to `uint256`;
- `getReservesPrices(uint256[])`, used here only at the PreTx fork for a
  consistent baseline batch; and
- no fallback oracle, addresses provider, cached price, `latestRoundData`
  timestamp check, or decimal conversion.

Prices consumed by the Spoke are therefore positive, 8-decimal values in the
configured feed's output denomination. Every Main Spoke source at the pin
returns the deployment's normalized USD price.

The verified oracle storage layout is the only hard-coded AaveOracle storage
assumption: `_sources[reserveId]` is
`keccak256(abi.encode(reserveId, uint256(1)))`. The Spoke implementation is
guarded through the standard ERC-1967 implementation slot. No V3 provider,
asset-keyed source mapping, fallback slot, or Chainlink round-data interface is
used.

## Main Spoke reserve policy

The PreTx Main Spoke has 14 contiguous reserve IDs:

| ID | Asset | Underlying | Hub asset ID | Decimals | Direct source | Verified source type |
| ---: | --- | --- | ---: | ---: | --- | --- |
| 0 | WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | 0 | 18 | `0x5424384B256154046E9667dDFaaa5e550145215e` | `EACAggregatorProxy` |
| 1 | wstETH | `0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0` | 1 | 18 | `0xe1D97bF61901B075E9626c8A2340a7De385861Ef` | `WstETHPriceCapAdapter` |
| 2 | weETH | `0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee` | 2 | 18 | `0x87625393534d5C102cADB66D37201dF24cc26d4C` | `WeETHPriceCapAdapter` |
| 3 | WBTC | `0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599` | 11 | 8 | `0xDaa4B74C6bAc4e25188e64ebc68DB5050b690cAc` | `CLSynchronicityPriceAdapterPegToBase` |
| 4 | cbBTC | `0xcBb7C0000aB88B473b1f5AFd9ef808440eED33BF` | 12 | 8 | `0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A` | `EACAggregatorProxy` |
| 5 | AAVE | `0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2dDAE9` | 15 | 18 | `0xF02C1e2A3B77c1cacC72f72B44f7d0a4c62e4a85` | `EACAggregatorProxy` |
| 6 | LINK | `0x514910771AF9Ca656af840dff83E8264EcF986CA` | 16 | 18 | `0xC7e9b623ed51F033b32AE7f1282b1AD62C28C183` | `EACAggregatorProxy` |
| 7 | USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | 5 | 6 | `0x3f73F03aa83B2A48ed27E964eD0fDb590332095B` | `PriceCapAdapterStable` |
| 8 | USDT | `0xdAC17F958D2ee523a2206206994597C13D831ec7` | 4 | 6 | `0x260326c220E469358846b187eE53328303Efe19C` | `PriceCapAdapterStable` |
| 9 | EURC | `0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c` | 10 | 6 | `0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3` | `EURPriceCapAdapterStable` |
| 10 | RLUSD | `0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD` | 7 | 18 | `0xf0eaC18E908B34770FDEe46d069c846bDa866759` | `PriceCapAdapterStable` |
| 11 | USDG | `0xe343167631d89B6Ffc58B88d6b7fB0228795491D` | 8 | 6 | `0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4` | `PriceCapAdapterStable` |
| 12 | frxUSD | `0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29` | 9 | 18 | `0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD` | `PriceCapAdapterStable` |
| 13 | GHO | `0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f` | 6 | 18 | `0xD110cac5d8682A3b045D5524a9903E031d70FCCd` | `GhoOracle` |

The assertion requires the live reserve count to equal the policy count, every
policy index to equal its reserve ID, the PreTx underlying and direct source to
match, and every direct source to be unique. Unique sources are required
because this PCL build does not expose the nested oracle calldata described
below.

## Mutable source graph

The production wrapper includes 22 write guards. These are not generic proxy
guesses:

- Chainlink `EACAggregatorProxy` inherits `Owned`; its packed active
  phase/aggregator is slot 2. Changing the active aggregator necessarily writes
  this slot, including a change followed by restoration.
- `PriceCapAdapterBase` stores the packed snapshot ratio, timestamp, and growth
  rate in slot 1 and the maximum yearly growth parameter in slot 2.
- `PriceCapAdapterStable` and `EURPriceCapAdapterStable` store their active cap
  in slot 2.

The guarded transitive EAC proxies are WETH/USD
`0x5424384B256154046E9667dDFaaa5e550145215e`, cbBTC/USD
`0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A`, AAVE/USD
`0xF02C1e2A3B77c1cacC72f72B44f7d0a4c62e4a85`, LINK/USD
`0xC7e9b623ed51F033b32AE7f1282b1AD62C28C183`, WBTC/BTC
`0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23`, and the underlying
USDC, USDT, RLUSD, USDG, frxUSD, EURC, and EUR feeds embedded in the cap
adapters. The cap adapters' immutable dependency getters were queried directly;
an immutable dependency cannot be replaced without replacing code.

Direct source replacement is guarded separately by scanning writes to every
`AaveOracle._sources[reserveId]` mapping slot. Spoke implementation and beacon
writes are guarded through their ERC-1967 slots. Extra verified slots can be
supplied to the production wrapper, and are checked for duplicates.

## Price-consuming operation coverage

The exact ABI selectors at `v0.5.11` are:

| Operation | Selector | Price behavior |
| --- | --- | --- |
| `borrow(uint256,uint256,address)` | `0xd6bda0c0` | Always refreshes and validates user account data; reads every active collateral/borrow reserve. |
| `withdraw(uint256,uint256,address)` | `0x0ad58d2f` | Reads prices only when the withdrawn reserve is currently collateral. |
| `liquidationCall(uint256,uint256,address,uint256,bool)` | `0xc2fa746c` | Reads active account prices, then explicit collateral and debt prices, and recalculates account data after a non-deficit liquidation. |
| `setUsingAsCollateral(uint256,bool,address)` | `0x9e35c533` | Disabling collateral recalculates prices; enabling only refreshes dynamic configuration. |
| `updateUserRiskPremium(address)` | `0x91c46d09` | Recalculates account data with current dynamic configuration. |
| `updateUserDynamicConfig(address)` | `0x826002e2` | Refreshes dynamic configuration and validates recalculated account data. |

`multicall(bytes[])` is `0xac9650d8`. Its delegatecall legs remain separate
committed trace nodes, so all price reads from all legs are scanned once at
transaction end.

Omissions are deliberate:

- `supply` (`0x852a56a5`) and `repay` (`0xb1e8f8ef`) do not call the oracle.
- `addReserve` and `updateReservePriceSource` validate a candidate source by
  calling `latestAnswer`, but do not use that answer to commit user risk,
  borrowing, withdrawal, or liquidation state. A later risk operation is
  protected, and source mapping writes in the same transaction are rejected.
- Hub accounting operations have no oracle dependency.
- Read-only account-data queries do not modify protocol state. If executed
  inside a transaction they may cause a conservative extra check, but cannot
  bypass one.
- The pinned Spoke has no native flash-loan callback. A surrounding protocol
  callback can call the Spoke, and those nested Spoke calls are covered.
  Reentrancy into an already executing Spoke operation is independently blocked
  by V4's `nonReentrant` modifier.

Only `getReservePrice(uint256)` (`0xd45c35ff`) is a committed consumption
surface. `getReservesPrices(uint256[])` (`0x7b5b8e9f`) is not called by the
Spoke's state-changing paths.

## Trace evidence and exact mapping

PCL 1.6.0 `-vvvv` proves all of the following:

1. A Spoke operation, nested callback operation, and delegatecall multicall leg
   are recorded with their real selector, success flag, parent, and depth.
2. Every Spoke-to-AaveOracle `getReservePrice` STATICCALL is recorded, but in
   this compiler/executor path its `TriggerCall.input` is empty. The
   implementation therefore does not claim that nested calldata is available.
3. Each price call has exactly one direct
   AaveOracle-to-configured-source `latestAnswer()` (`0x50d25bcd`) child.
   Source addresses are unique in the protected deployment, so the child target
   maps the parent call to an exact reserve.
4. `callOutputAt` exposes both the child `int256` answer and the parent
   `uint256` oracle return. The assertion requires both to be 32 bytes, the
   source answer to be positive, and the values to be exactly equal before
   applying the deviation envelope.
5. A reverted-and-caught borrow and its oracle subtree are absent from
   `matchingCalls`, even if `successOnly` is disabled. Only committed calls
   contribute evidence.

An unmatched parent price call, zero/multiple matching source children,
malformed output, non-positive answer, source/parent output mismatch, unknown
source, or incomplete policy fails closed.

The PreTx batch is called on the configured oracle at the PreTx fork. Source
identity is also read at PreTx. No PostTx-selected oracle or source is ever used
to construct a PreTx baseline.

## Bounds and gas

Both parent oracle calls and source-call scans request `maxTraceCalls + 1` and
fail if the configured maximum is exceeded. Total source matches across all
configured sources are also bounded. This can conservatively reject a
transaction that deliberately spams the same source outside Aave; it cannot
silently truncate an Aave read.

Measured with PCL 1.6.0 and the Aave profile:

| Scenario | Assertion gas |
| --- | ---: |
| Stable two-reserve borrow | 267,102 |
| Manipulated two-operation multicall, rejection path | 283,524 |
| Nested callback manipulation, rejection path | 267,451 |
| Stable one-reserve/two-operation multicall | 206,353 |
| Stable 14-reserve sweep plus 22 production-equivalent config guards | 1,792,565 |
| Two stable 14-reserve sweeps plus 22 guards | 2,881,782 |

The realistic multicall stays below the requested 3,000,000 production budget
with 118,218 gas of measured margin. PCL 1.6.0's local CredibleTest runner still
enforces a legacy 300,000 assertion ceiling. The two realistic tests therefore
expect the runner's `Assertion exceeded gas limit` wrapper while `-vvvv`
reports the complete measured execution cost. The single-operation, callback,
rejection, and small multicall behavioral tests run normally under that local
ceiling.

## Native checks and residual risk

Aave V4 natively requires a configured source, 8 source decimals at
configuration time, and a positive `latestAnswer` at consumption time. Borrow,
withdraw, and configuration-refresh paths validate health factor using the
price they just read. Liquidation validates eligibility and calculates amounts
using current prices. None of those checks asks whether that current price was
temporarily changed after transaction start; health factor and liquidation
math can be internally consistent around an attacker-selected transient price.
The V4 functions also expose no general user-provided oracle-deviation bound.

This invariant adds a transaction-start anchor and checks the exact price
returned to Aave at every committed consumption. Restoring the feed, source,
adapter cap, proxy aggregator, or Spoke implementation before transaction end
does not erase the trace output or write evidence.

Residual limitations and false-positive risks:

- A price already manipulated before PreTx is accepted as the baseline. An
  independent reference-price/freshness assertion is complementary, not a
  replacement.
- V4 intentionally calls legacy `latestAnswer`; no timestamp or round metadata
  reaches AaveOracle. This assertion matches V4 semantics and cannot infer
  staleness. A separate source-specific freshness assertion should use verified
  downstream interfaces.
- Legitimate reserve additions, source migrations, Spoke upgrades, guarded
  cap changes, or Chainlink aggregator rotations fail closed until the pinned
  assertion is redeployed.
- The 118k realistic-multicall gas margin is narrow. Increase in reserve count,
  guard count, or multicall price sweeps requires remeasurement; a lower
  `maxTraceCalls` bounds cost but can conservatively reject large transactions.
- A future deployment that shares one direct source across reserve IDs cannot
  use source-address mapping safely. This constructor rejects shared sources;
  support requires nested oracle calldata from the executor or another verified
  reserve-context signal.
