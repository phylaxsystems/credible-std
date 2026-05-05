# Uniswap V4 Assertion — Base Mainnet Deployment Handoff

Top 5 Uniswap V4 pools on Base, with full `PoolKey` reconstructed and verified against on-chain `poolId`.

## Adopter

All 5 assertion instances attach to the **same** adopter — the V4 PoolManager singleton on Base.

| Field | Value |
|---|---|
| Chain | Base (chainId `8453`) |
| Adopter (PoolManager) | `0x498581fF718922c3f8e6A244956aF099B2652b2b` |
| Assertion contract | `src/protection/swaps/examples/UniswapV4PoolManagerAssertion.sol` |
| Assertion constructor | `(address manager_, IUniswapV4PoolManagerLike.PoolKey memory poolKey_)` |

Deploy 5 separate instances of `UniswapV4PoolManagerAssertion`, one per pool, each constructed with `manager_ = 0x498581fF718922c3f8e6A244956aF099B2652b2b` and the corresponding `poolKey_` below.

## Token addresses (Base)

| Symbol | Address | Decimals |
|---|---|---|
| ETH (native) | `0x0000000000000000000000000000000000000000` | 18 |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 |
| USDT | `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2` | 6 |
| cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | 8 |

## Pools

PoolKey ordering rule: `currency0 < currency1` numerically. Native ETH (`0x0`) is always `currency0`. Each `poolId = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks))` — every entry below has been verified.

### 1. ETH / cbBTC — 0.3% — **with hook**

| Field | Value |
|---|---|
| `poolId` | `0x2c9ba05f9226dcd6ec6442ed22907dd8d50ebc3cacfb9b67cad10e90636f1a73` |
| `currency0` | `0x0000000000000000000000000000000000000000` (ETH) |
| `currency1` | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` (cbBTC) |
| `fee` | `3000` (0.3%) |
| `tickSpacing` | `300` |
| `hooks` | `0x5cd525c621AfCa515bF58631D4733FbA7b72aaE4` (`VerifiedPoolsBasicHook`, verified on Basescan) |

> Note: this pool uses non-default `tickSpacing` (300, not 60) and a hook that enforces pool-operator policy. Triggers from the assertion will fire on every `swap`/`modifyLiquidity`/`donate` against the PoolManager — the hook's pre/post callbacks run inside the same call frame and may affect token deltas the assertion observes.

### 2. ETH / cbBTC — 0.009%

| Field | Value |
|---|---|
| `poolId` | `0x8fe985a6a484e89af85189f7efc20de0183d0c3415bf2a9ceefa5a7d1af879e5` |
| `currency0` | `0x0000000000000000000000000000000000000000` (ETH) |
| `currency1` | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` (cbBTC) |
| `fee` | `90` (0.009%) |
| `tickSpacing` | `2` |
| `hooks` | `0x0000000000000000000000000000000000000000` |

### 3. ETH / USDC — 0.3%

| Field | Value |
|---|---|
| `poolId` | `0xe070797535b13431808f8fc81fdbe7b41362960ed0b55bc2b6117c49c51b7eb9` |
| `currency0` | `0x0000000000000000000000000000000000000000` (ETH) |
| `currency1` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| `fee` | `3000` (0.3%) |
| `tickSpacing` | `60` |
| `hooks` | `0x0000000000000000000000000000000000000000` |

### 4. ETH / USDC — 0.05%

| Field | Value |
|---|---|
| `poolId` | `0x96d4b53a38337a5733179751781178a2613306063c511b78cd02684739288c0a` |
| `currency0` | `0x0000000000000000000000000000000000000000` (ETH) |
| `currency1` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| `fee` | `500` (0.05%) |
| `tickSpacing` | `10` |
| `hooks` | `0x0000000000000000000000000000000000000000` |

### 5. USDC / USDT — 0.002%

| Field | Value |
|---|---|
| `poolId` | `0xd3020570106c58635ff7f549659c4c310409c9a5d698cb826842bc8a39e3ce81` |
| `currency0` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| `currency1` | `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2` (USDT) |
| `fee` | `20` (0.002%) |
| `tickSpacing` | `1` |
| `hooks` | `0x0000000000000000000000000000000000000000` |

## Constructor argument tuples (Solidity)

For passing as the `poolKey_` arg to `UniswapV4PoolManagerAssertion`:

```solidity
// 1. ETH/cbBTC 0.3%
PoolKey({
    currency0: Currency.wrap(0x0000000000000000000000000000000000000000),
    currency1: Currency.wrap(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf),
    fee: 3000,
    tickSpacing: 300,
    hooks: IHooks(0x5cd525c621AfCa515bF58631D4733FbA7b72aaE4)
});

// 2. ETH/cbBTC 0.009%
PoolKey({
    currency0: Currency.wrap(0x0000000000000000000000000000000000000000),
    currency1: Currency.wrap(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf),
    fee: 90,
    tickSpacing: 2,
    hooks: IHooks(0x0000000000000000000000000000000000000000)
});

// 3. ETH/USDC 0.3%
PoolKey({
    currency0: Currency.wrap(0x0000000000000000000000000000000000000000),
    currency1: Currency.wrap(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913),
    fee: 3000,
    tickSpacing: 60,
    hooks: IHooks(0x0000000000000000000000000000000000000000)
});

// 4. ETH/USDC 0.05%
PoolKey({
    currency0: Currency.wrap(0x0000000000000000000000000000000000000000),
    currency1: Currency.wrap(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913),
    fee: 500,
    tickSpacing: 10,
    hooks: IHooks(0x0000000000000000000000000000000000000000)
});

// 5. USDC/USDT 0.002%
PoolKey({
    currency0: Currency.wrap(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913),
    currency1: Currency.wrap(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2),
    fee: 20,
    tickSpacing: 1,
    hooks: IHooks(0x0000000000000000000000000000000000000000)
});
```

## Verification

Each row above was confirmed by computing `keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks))` and matching it against the published `poolId`. Reproduce with:

```bash
cast keccak $(cast abi-encode 'f(address,address,uint24,int24,address)' \
  <currency0> <currency1> <fee> <tickSpacing> <hooks>)
```

Pool 1's parameters (the only one with a hook) were additionally cross-checked against the on-chain `Initialize` event emitted by the PoolManager.
