# Credible Block Guard

A reusable mixin that gates contract functions on **block credibility**: a guarded function only
executes while the current block is credible (built by a Credible Layer builder that enforces
assertions), and **fails open** if the credible builder set goes offline so the contract is never
permanently bricked.

This is the general-purpose form of the credibility gate. `CredibleSafeGuard`
(`src/protection/safe/CredibleSafeGuard.sol`) is the same decision wired into a Safe transaction
guard; inherit `CredibleBlockGuard` directly when you want to protect your own functions.

## Files

- `ICredibleRegistry.sol` — read interface for the on-chain Credible Registry
  (`isCredibleBlock(blockNumber)`, `lastCredibleBlock()`), mirroring `phylaxsystems/credible-registry`.
- `CredibleBlockGuard.sol` — abstract base contract providing the `onlyCredibleBlock` modifier.

## Usage

```solidity
import {CredibleBlockGuard} from "credible-std/protection/credible_block/CredibleBlockGuard.sol";
import {ICredibleRegistry} from "credible-std/protection/credible_block/ICredibleRegistry.sol";

contract MyVault is CredibleBlockGuard {
    // failOpenThreshold ~= number of blocks the chain produces in ~15 minutes
    constructor(ICredibleRegistry registry, uint256 failOpenThreshold)
        CredibleBlockGuard(registry, failOpenThreshold)
    {}

    function withdraw(uint256 amount) external onlyCredibleBlock {
        // only runs in a credible block, or while the guard is failing open
    }
}
```

## Decision

`onlyCredibleBlock` runs the following before the function body:

1. **Fail open** — if the most recent credible block is more than `failOpenBlockThreshold` blocks
   behind the current block, the builder set looks offline: allow the call. This prevents a
   stalled builder set from permanently locking the contract.
2. Otherwise the builder set is live, so the current block **must** be credible; if it is not, the
   call reverts with `NonCredibleBlock`.
3. If the current block is itself credible, the call is always allowed.

`isCurrentBlockAllowed()` and `failOpenActive()` expose the same decision as view helpers for
off-chain inspection.

## Fail-open window

The product requirement is "fail open after ~15 minutes with no credible blocks". The registry
records credibility by block number and does not expose timestamps, so the window is a block count
approximating the chain's 15-minute budget:

| Block time | ~15 min |
| ---------- | ------- |
| ~12s (Ethereum mainnet) | ~75 blocks |
| ~2s (typical L2) | ~450 blocks |
| ~1s | ~900 blocks |

Both the registry address and the threshold are immutable (configurable per deployment); re-pointing
or re-tuning means redeploying the inheriting contract.

## Tests

```sh
forge test --match-path "test/protection/credible_block/CredibleBlockGuard.t.sol"
```
