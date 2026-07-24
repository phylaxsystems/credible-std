# Initial Protocol Manager

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

## Files

- `IInitialProtocolManager.sol` — the interface the state oracle reads (`initialProtocolManager()`).
- `InitialProtocolManager.sol` — abstract base that implements the interface with an immutable set
  at deployment.

## Usage

Inherit the abstract base and forward the manager address to the constructor:

```solidity
import {InitialProtocolManager} from "credible-std/protection/initial_protocol_manager/InitialProtocolManager.sol";

contract MyProtectedContract is InitialProtocolManager {
    constructor(address manager) InitialProtocolManager(manager) {}
}
```

The public immutable auto-generates the `initialProtocolManager()` getter that satisfies the
interface. The manager is immutable, so the value the state oracle reads is exactly what the
deployer committed to; changing it means redeploying. Once the protocol is initialized in the
Credible Layer, the manager is managed there rather than through this value.

Contracts that only need to declare the manager (without the zero-address check or a base
constructor) can implement `IInitialProtocolManager` directly instead.

`CredibleSafeGuard` (`src/protection/safe/CredibleSafeGuard.sol`) inherits this base, so a guard
deployment declares its own protocol manager and the state oracle can onboard it without a manual
review round.
