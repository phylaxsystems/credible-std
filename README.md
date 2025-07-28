# credible-std

credible-std is a standard library for implementing assertions in the Phylax Credible Layer (PCL). It provides the core contracts and interfaces needed to create and manage assertions for smart contract security monitoring.

## Overview

The Phylax Credible Layer (PCL) is a security framework that enables real-time monitoring and validation of smart contract behavior through assertions. credible-std provides the foundational contracts and utilities needed to implement these assertions.

### Key Components

- `Credible.sol`: Base contract that provides access to the PhEvm precompile for assertion validation
- `Assertion.sol`: Abstract contract for implementing assertions with trigger registration and validation logic
- `StateChanges.sol`: Utilities for tracking and validating contract state changes with type-safe conversions
- `TriggerRecorder.sol`: Manages assertion triggers for function calls, storage changes, and balance changes
- `PhEvm.sol`: Interface for the PhEvm precompile that enables assertion validation
- `CredibleTest.sol`: Testing utilities for assertion development and validation

## Features

- **Trigger System**: Register triggers for function calls, storage changes, and balance changes to monitor specific contract behaviors
- **State Change Tracking**: Type-safe utilities for monitoring and validating contract state changes with built-in conversion helpers
- **Testing Framework**: Comprehensive testing utilities for assertion development with built-in validation helpers
- **PhEvm Integration**: Direct access to the PhEvm precompile for advanced assertion logic and validation

You can find detailed documentation on the Credible Layer and how to use the credible-std library in the [Credible Layer Documentation](https://docs.phylax.systems/credible/credible-introduction).

## Installation

### Using Foundry

Add the following to your `foundry.toml`:

```toml
[dependencies]
credible-std = { git = "https://github.com/phylaxsystems/credible-std.git" }
```

Then run:

```bash
forge install
```

Alternatively you can install the package using forge:

```bash
forge install phylax-systems/credible-std
```

### Using Hardhat

Add the dependency to your `package.json`:

```json
{
  "dependencies": {
    "credible-std": "github:phylaxsystems/credible-std"
  }
}
```

Then run:

```bash
npm install
```

## Usage

### Assertion Lifecycle

1. Create an assertion contract that inherits from `Assertion`
2. Initialize the assertion in the constructor with the contract address you want to monitor
3. Register triggers in the `triggers()` function for when the assertion should be checked
4. Implement validation logic in your assertion function(s)
5. Add the assertion to your test environment using `cl.addAssertion()`
6. Test the assertion using `cl.validate()`

### Creating an Assertion

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/src/Assertion.sol"; // Credible Layer precompiles
import {Ownable} from "../../src/Ownable.sol"; // Contract to write assertions for

contract OwnableAssertion is Assertion {
    Ownable ownable;

    constructor(address ownable_) {
        ownable = Ownable(ownable_); // Define address of Ownable contract
    }

    // Define selectors for the assertions, several assertions can be defined here
    // This function is required by the Assertion interface
    function triggers() external view override {
        registerCallTrigger(this.assertionOwnershipChange.selector); // Register the selector for the assertionOwnershipChange function
    }

    // This function is used to check if the ownership has changed
    // Get the owner of the contract before and after the transaction
    // Return false if the owner has changed, true if it has not
    function assertionOwnershipChange() external {
        ph.forkPreTx(); // Fork the pre-state of the transaction
        address preOwner = ownable.owner(); // Get the owner of the contract before the transaction
        ph.forkPostTx(); // Fork the post-state of the transaction
        address postOwner = ownable.owner(); // Get the owner of the contract after the transaction
        require(postOwner == preOwner, "Ownership has changed"); // revert if the owner has changed
    }
}
```

For a detailed guide on how to write assertions check out the [Writing Assertions](https://docs.phylax.systems/credible/pcl-assertion-guide) section of the documentation.

### Available Cheatcodes

The credible-std provides several cheatcodes for assertion validation:

<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> 5a9fa20 (chore: consistent naming)
- `forkPreTx()`: Forks to the state prior to the assertion triggering transaction.
- `forkPostTx()`: Forks to the state after the assertion triggering transaction.
- `forkPreCall(uint256 id)`: Forks to the state at the start of call execution for the specified id. `getCallInputs(..)` can be used to get ids to fork to.
- `forkPostCall(uint256 id)`: Forks to the state after the call execution for the specified id. `getCallInputs(..)` can be used to get ids to fork to.
<<<<<<< HEAD
=======
- `forkPreTx()`: Forks to the state prior to the assertion triggering transaction
- `forkPostTx()`: Forks to the state after the assertion triggering transaction
>>>>>>> e57cf28 (chore: remove mocks and update fork names throughout)
=======
>>>>>>> 5a9fa20 (chore: consistent naming)
- `load(address target, bytes32 slot)`: Loads a storage slot from an address
- `getLogs()`: Retrieves logs from the assertion triggering transaction
- `getCallInputs(address target, bytes4 selector)`: Gets call inputs for a given target and selector. Includes id for call forking.
- `getStateChanges(address contractAddress, bytes32 slot)`: Gets state changes for a given contract and storage slot
- `getAssertionAdopter()`: Get assertion adopter contract address associated with the assertion triggering transaction

These cheatcodes can be accessed through the `ph` instance in your assertion contracts, which is provided by the `Credible` base contract.

### Testing Assertions

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Credible} from "credible-std/src/Credible.sol";
import {OwnableAssertion} from "../src/OwnableAssertion.sol";
import {Ownable} from "../../src/Ownable.sol";
import {CredibleTest} from "credible-std/src/CredibleTest.sol";
import {Test} from "forge-std/Test.sol";

contract TestOwnableAssertion is CredibleTest, Test {
    // Contract state variables
    Ownable public assertionAdopter;
    address public initialOwner = address(0xdead);
    address public newOwner = address(0xdeadbeef);

    function setUp() public {
        assertionAdopter = new Ownable();
        vm.deal(initialOwner, 1 ether);
    }

    function test_assertionOwnershipChanged() public {
        address aaAddress = address(assertionAdopter);
        string memory label = "OwnableAssertion";

        // Associate the assertion with the protocol
        // cl will manage the correct assertion execution under the hood when the protocol is being called
        cl.addAssertion(label, aaAddress, type(OwnableAssertion).creationCode, abi.encode(assertionAdopter));

        vm.prank(initialOwner);
        vm.expectRevert("Assertions Reverted"); // If the assertion fails, it will revert with this message
        cl.validate(
            label, aaAddress, 0, abi.encodePacked(assertionAdopter.transferOwnership.selector, abi.encode(newOwner))
        );
    }
}
```

For a detailed guide on how to test assertions check out the [Testing Assertions](https://docs.phylax.systems/credible/testing-assertions) section of the documentation.
