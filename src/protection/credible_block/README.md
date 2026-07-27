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
- `IInitialProtocolManager.sol` — interface the state oracle reads to discover a contract's intended
  protocol manager (`initialProtocolManager()`). See
  [Initial protocol manager](#initial-protocol-manager).
- `InitialProtocolManager.sol` — abstract base implementing that interface with an immutable set at
  deployment.

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

## Initial protocol manager

Every protected contract needs a **protocol manager**: the address allowed to manage that
contract's assertions in the Credible Layer. Exposing the intended manager on the contract itself
lets the Credible Layer state oracle set it automatically, with no manual review round.

Because the address is defined by the contract's own code, **deploying the contract is the
ownership proof** — whoever controlled the deployment chose the manager. This is what makes updated
or redeployed contracts self-verifying: the state oracle calls `initialProtocolManager()` on the
new contract and registers the returned address, with no separate claim step.

Implementing this interface is **optional**. Contracts that don't expose it (for example,
already-deployed contracts you can't change) go through manual verification instead, where Phylax
confirms ownership directly and sets the manager.

Inherit the abstract base and forward the manager address to the constructor:

```solidity
import {InitialProtocolManager} from "credible-std/protection/credible_block/InitialProtocolManager.sol";

contract MyProtectedContract is InitialProtocolManager {
    constructor(address manager) InitialProtocolManager(manager) {}
}
```

The public immutable auto-generates the `initialProtocolManager()` getter that satisfies the
interface. The manager is immutable, so the value the state oracle reads is exactly what the
deployer committed to; changing it means redeploying. Once the protocol is initialized in the
Credible Layer, the manager is managed there rather than through this value.

Contracts that only need to declare the manager (without the zero-address check or a base
constructor) can implement `IInitialProtocolManager` directly instead:

```solidity
import {IInitialProtocolManager} from "credible-std/protection/credible_block/IInitialProtocolManager.sol";

contract MyProtectedContract is IInitialProtocolManager {
    function initialProtocolManager() external view returns (address) {
        return 0xBEEF...;
    }
}
```

## Tests

```sh
forge test --match-path "test/protection/credible_block/CredibleBlockGuard.t.sol"
forge test --match-path "test/protection/credible_block/InitialProtocolManager.t.sol"
```
