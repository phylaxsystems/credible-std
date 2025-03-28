# Credible-std

Credible-std is a standard library for implementing assertions in the Phylax Credible Layer (PCL). It provides the core contracts and interfaces needed to create and manage assertions for smart contract security monitoring.

## Overview

The Phylax Credible Layer (PCL) is a security framework that enables real-time monitoring and validation of smart contract behavior through assertions. Credible-std provides the foundational contracts and utilities needed to implement these assertions.

### Key Components

- `Credible.sol`: Base contract that provides access to the PhEvm precompile
- `Assertion.sol`: Abstract contract for implementing assertions with trigger registration
- `StateChanges.sol`: Utilities for tracking and validating state changes
- `TriggerRecorder.sol`: Manages assertion triggers for function calls and state changes
- `PhEvm.sol`: Interface for the PhEvm precompile
- `CredibleTest.sol`: Testing utilities for assertion development

TODO: fix link
You can find detailed documentation on the Credible Layer and how to use the credible-std library in the [Credible Layer Documentation](ADD_LINK_ONCE_DOCUMENTATION_IS_PUBLISHED).

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

### Creating an Assertion

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/src/Assertion.sol";

contract MyAssertion is Assertion {
    function triggers() external view override {
        // Register triggers for your assertion
        registerCallTrigger(this.validate.selector);
    }

    function validate() external view {
        // Implement your assertion logic here
        // This will be called when triggers are activated
    }
}
```

TODO: fix link
For a detailed guide on how to create an assertion check out the [Writing Assertions](INSERT_LINK_ONCE_DOCUMENTATION_IS_PUBLISHED) section of the documentation.

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
        string memory label = "Ownership has changed";

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

TODO: fix link

For a detailed guide on how to test assertions check out the [Testing Assertions](INSERT_LINK_ONCE_DOCUMENTATION_IS_PUBLISHED) section of the documentation.

## Features

- **Trigger System**: Register triggers for function calls, storage changes, and balance changes
- **State Change Tracking**: Built-in utilities for monitoring contract state changes
- **Testing Framework**: Comprehensive testing utilities for assertion development
- **PhEvm Integration**: Direct access to the PhEvm precompile for advanced assertion logic
