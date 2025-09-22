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

- `forkPreTx()`: Forks to the state prior to the assertion triggering transaction.
- `forkPostTx()`: Forks to the state after the assertion triggering transaction.
- `forkPreCall(uint256 id)`: Forks to the state at the start of call execution for the specified id. `getCallInputs(..)` can be used to get ids to fork to.
- `forkPostCall(uint256 id)`: Forks to the state after the call execution for the specified id. `getCallInputs(..)` can be used to get ids to fork to.
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

import {OwnableAssertion} from "../src/OwnableAssertion.a.sol";
import {Ownable} from "../../src/Ownable.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";
import {Test} from "forge-std/Test.sol";

contract TestOwnableAssertion is CredibleTest, Test {
    // Contract state variables
    Ownable public assertionAdopter;
    address public initialOwner = address(0xf00);
    address public newOwner = address(0xdeadbeef);

    // Set up the test environment
    function setUp() public {
        assertionAdopter = new Ownable(initialOwner);
        vm.deal(initialOwner, 1 ether);
    }

    // Test case: Ownership changes should trigger the assertion
    function test_assertionOwnershipChanged() public {
        cl.assertion({
            adopter: address(assertionAdopter),
            createData: type(OwnableAssertion).creationCode,
            fnSelector: OwnableAssertion.assertionOwnershipChange.selector
        });

        // Simulate a transaction that changes ownership
        vm.prank(initialOwner);
        vm.expectRevert("Ownership has changed");
        assertionAdopter.transferOwnership(newOwner);
    }

    // Test case: No ownership change should pass the assertion
    function test_assertionOwnershipNotChanged() public {
        cl.assertion({
            adopter: address(assertionAdopter),
            createData: type(OwnableAssertion).creationCode,
            fnSelector: OwnableAssertion.assertionOwnershipChange.selector
        });

        // Simulate a transaction that doesn't change ownership (transferring to same owner)
        vm.prank(initialOwner);
        assertionAdopter.transferOwnership(initialOwner);
    }
}
```

For a detailed guide on how to test assertions check out the [Testing Assertions](https://docs.phylax.systems/credible/testing-assertions) section of the documentation.

## Backtesting

The credible-std library includes backtesting functionality that allows you to test your assertions against historical blockchain data. This enables you to validate assertion correctness on real transactions before deploying to production.

### Components

- `CredibleTestWithBacktesting.sol`: Extended test base that provides backtesting functionality
- `BacktestingTypes.sol`: Type definitions for backtesting configuration and results
- `BacktestingUtils.sol`: Utility functions for parsing and processing blockchain data
- `transaction_fetcher.sh`: Bash script for fetching historical transactions (minimal dependencies)

### Setup

**Configure foundry.toml**: Add the backtesting profile to your `foundry.toml`:

```toml
[profile.backtesting]
src = "src"
out = "out"
libs = ["lib"]
ffi = true
gas_limit = 100000000
timeout = 300
test = "test"
```

### Creating Backtesting Tests

Create a test contract that inherits from `CredibleTestWithBacktesting`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CredibleTestWithBacktesting} from "../../src/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "../../src/utils/BacktestingTypes.sol";
import {ERC20Assertion} from "../fixtures/backtesting/ERC20Assertion.a.sol";

contract MyBacktestingTest is CredibleTestWithBacktesting {
    function testERC20Backtesting() public {
        executeBacktest({
            targetContract: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC on Sepolia
            endBlock: 8925198,
            blockRange: 100,
            assertionCreationCode: type(ERC20Assertion).creationCode,
            assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
            rpcUrl: "https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
        });
    }
}
```

### Configuration Options

The backtesting system accepts several configuration parameters:

- `targetContract`: The contract address to monitor for transactions
- `endBlock`: The latest block number to include in the test
- `blockRange`: Number of blocks to test (from `endBlock - blockRange + 1` to `endBlock`)
- `assertionCreationCode`: The bytecode for creating your assertion contract
- `assertionSelector`: The function selector of your assertion function
- `rpcUrl`: The RPC endpoint URL for fetching blockchain data

### Running Backtesting Tests

Use the `pcl` command with the backtesting profile:

```bash
# Set your RPC URL
export RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"

# Run backtesting tests
FOUNDRY_PROFILE=backtesting pcl test --match-test testERC20Backtesting -vvv

# Or run all backtesting tests
FOUNDRY_PROFILE=backtesting pcl test --match-path "**/backtesting/**" -vvv
```

### Understanding Results

The backtesting system provides detailed results including:

- **Total Transactions**: Number of transactions found in the specified block range
- **Processed Transactions**: Number of transactions successfully processed
- **Successful Validations**: Number of transactions that passed assertion validation
- **Failed Validations**: Number of transactions that failed assertion validation
- **Success Rate**: Percentage of successful validations

> **⚠️ Important**: If you see any **Failed Validations**, this indicates potential issues with your assertion logic. Check the detailed test output to identify false positives - transactions that should have passed but failed validation.

Example output:

```bash
==========================================
           BACKTESTING SUMMARY
==========================================
Block Range: 8925189 - 8925198
Total Transactions: 26
Processed Transactions: 26
Successful Validations: 26
Failed Validations: 0

Success Rate: 100%
================================
```
