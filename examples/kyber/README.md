# kyber examples

Assertion examples for the KyberSwap **MetaAggregationRouterV2** aggregator router
(`0x6131B5fae19EA4f9D964eAc0408E4408b66337b5`, same address across chains). The router is a
single fixed-address, non-proxy `Ownable` contract that settles aggregator swaps non-custodially
and pulls source funds through standing ERC20 allowances.

These mirror the structure of the `zeroex` Settler examples, adapted to KyberSwap's
standing-allowance model.

## Build

```sh
FOUNDRY_PROFILE=kyber forge build
```

## Test

```sh
FOUNDRY_PROFILE=kyber pcl test --match-contract KyberMetaAggregationRouterAssertionTest
```

The tests run against `KyberSwapMocks.sol`, a faithful MetaAggregationRouterV2 settlement model that
reproduces the observable on-chain behavior: standing-allowance pulls to `srcReceivers`/`feeReceivers`,
executor dispatch via a low-level `call` (the same opcode the arbitrary-call drain abuses), a
constant-product (Uniswap V2-style) pool, fee-on-transfer tokens, `swapSimpleMode`, `swapGeneric`,
the `_PARTIAL_FILL` pro-rated min-return rule, and a router whose own min-return guard can be toggled
off to model a compromised/buggy deployment.

The live router enforces min-return against the recipient's true credited balance, so the
`assertReceiverGetsMinReturn` check is **path-independent defense-in-depth**: it re-pins the
user-signed minimum from outside the router's accounting and would catch a settlement path that
bypasses that guard. The mock's toggle (`setEnforceMinReturn(false)`) models exactly that bypass.

Coverage (25 behavior tests):

- min-return: honest swap, exact boundary, third-party recipient, swapSimpleMode honest/underpaid,
  swapGeneric honest/underpaid, unset-receiver resolves-to-initiator honest/underpaid, partial-fill
  no-false-positive, native-ETH skip, zero-minimum skip, fee-on-transfer shortfall, and a
  compromised-router underpayment.
- approval: honest initiator pull, full-swap no-false-positive (pool payout + fee leg), finite- and
  max-approval arbitrary-call drains, a permit-then-drain that creates the bystander allowance
  mid-call, router spending its own inventory, a third party paying its own inventory, swapGeneric
  honest/drain, and swapSimpleMode honest/drain.

## Files

- `KyberMetaAggregationRouterAssertion.sol` — the two protected invariants.
- `KyberMetaAggregationRouterHelpers.sol` — fork reads, calldata decoding, allowance/log scanning.
- `KyberMetaAggregationRouterInterfaces.sol` — `SwapDescriptionV2` / `SwapExecutionParams` and minimal interfaces.
- `test/KyberSwapMocks.sol` — faithful router/pool/executor/token mocks for the test suite.

## Assertions

- **`assertNoThirdPartyAllowanceDrain`** — a swap may only exercise the router allowance of its own
  initiator (the account the router debits via `transferFrom`). It trips when the settlement pulls
  tokens out of a different account that had pre-approved the router, i.e. someone crafted calldata
  to drain a bystander's standing approval. This is the Kyber counterpart of the 0x
  `assertNoPreApprovedTransferSource` check; because Kyber legitimately uses standing allowances,
  the initiator's own approval is explicitly exempt. The check flags both pre-existing standing
  allowances and allowances a swap creates mid-call: the router runs `desc.permit` (with an
  attacker-supplied `owner`/`spender`) before any funds move, so a bystander's signed EIP-2612
  permit can mint `allowance(victim, router)` inside the call — invisible to a pre-call allowance
  read. Scanning for the in-frame `Approval(victim, router)` the permit emits closes that
  permit-then-drain blind spot.

- **`assertReceiverGetsMinReturn`** — the declared recipient must be credited at least the signed
  `minReturnAmount` of `dstToken`, verified as a fork-aware balance delta across the call. The live
  router already enforces this against the same recipient balance delta, so the check is
  defense-in-depth that re-pins the user-signed minimum should a settlement path bypass that guard.
  An unset recipient (`dstReceiver == address(0)`) is resolved to the initiator, because the router
  credits `msg.sender` in that case. Out of scope (skipped to avoid false positives): native-asset
  payouts (`dstToken == ETH_SENTINEL`, ERC20-balance surface only), zero-minimum swaps, and
  `_PARTIAL_FILL` orders (the router holds those to a pro-rated minimum keyed to the actual spent
  amount, which a flat `minReturnAmount` floor would not match).

## Coverage notes

- All three fund-moving entry points are registered, each verified against the mainnet
  `MetaAggregationRouterV2` source (`0x6131B5fae19EA4f9D964eAc0408E4408b66337b5`, `pragma 0.8.9`):
  `swap` (`0xe21fd0e9`), `swapGeneric` (`0x59e50fed`), and `swapSimpleMode` (`0x8af033fb`). Each
  selector cryptographically pins the `SwapExecutionParams` / `SwapDescriptionV2` layout.
- `swap` internally dispatches to `swapSimpleMode` when the `_SIMPLE_SWAP` (`0x20`) flag is set;
  that path retains the `swap` selector, so decoding stays driven by the entry selector and needs no
  separate trigger.
- On-chain, `swap` forces the executor `callBytes` selector while `swapGeneric` raw-calls a
  whitelisted target with caller-supplied calldata — the more direct arbitrary-call drain surface.
  The allowance invariant is path-independent, so registering both closes the vector regardless of
  which entry point or future whitelisted-executor compromise is used to exercise it.
