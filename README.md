# credible-std

Standard library for implementing assertions in the Phylax Credible Layer (PCL). Provides the core contracts and interfaces needed to create, test, and validate assertions for smart contract security monitoring.

## Documentation

Full API documentation is available at: https://phylaxsystems.github.io/credible-std

## Installation

### Using Foundry (Recommended)

Install the latest stable release:

```bash
forge install phylaxsystems/credible-std@0.4.0
```

Or install from master (latest development version):

```bash
forge install phylaxsystems/credible-std
```

Add the remapping to your `remappings.txt`:

```
credible-std/=lib/credible-std/src/
```

## Overview

The Phylax Credible Layer (PCL) is a security framework that enables real-time monitoring and validation of smart contract behavior through assertions. credible-std provides the foundational contracts and utilities needed to implement these assertions.

### Key Components

| Contract | Description |
|----------|-------------|
| `Assertion.sol` | Base contract for creating assertions with trigger registration |
| `Credible.sol` | Provides access to the PhEvm precompile for transaction state inspection |
| `PhEvm.sol` | Interface for the PhEvm precompile (state forking, logs, call inputs) |
| `StateChanges.sol` | Type-safe utilities for tracking contract state changes |
| `TriggerRecorder.sol` | Interface for registering assertion triggers |
| `CredibleTest.sol` | Base contract for testing assertions with Forge |
| `CredibleTestWithBacktesting.sol` | Extended test contract with historical transaction backtesting |

## Features

- **Trigger System**: Register triggers for function calls, storage changes, and balance changes
- **State Inspection**: Fork to pre/post transaction state, inspect logs, call inputs, and storage
- **Type-Safe State Changes**: Built-in converters for uint256, address, bool, and bytes32 state changes
- **Testing Framework**: Test assertions locally with Forge before deployment
- **Backtesting**: Validate assertions against historical blockchain transactions
- **Internal Call Detection**: Automatically detect transactions that call your contract internally (not just direct calls)

## Quick Start

### 1. Create an Assertion

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";

contract MyAssertion is Assertion {
    // Register when this assertion should run
    function triggers() external view override {
        // Run on any call to the adopter contract
        registerCallTrigger(this.checkInvariant.selector);

        // Or run only on specific function calls
        // registerCallTrigger(this.checkInvariant.selector, ITarget.deposit.selector);
    }

    // Implement your invariant check
    function checkInvariant() external {
        address target = ph.getAssertionAdopter();

        ph.forkPreTx();
        uint256 balanceBefore = target.balance;

        ph.forkPostTx();
        uint256 balanceAfter = target.balance;

        require(balanceAfter >= balanceBefore, "Balance decreased unexpectedly");
    }
}
```

### 2. Test Your Assertion

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CredibleTest} from "credible-std/CredibleTest.sol";
import {Test} from "forge-std/Test.sol";
import {MyAssertion} from "./MyAssertion.sol";
import {MyContract} from "./MyContract.sol";

contract TestMyAssertion is CredibleTest, Test {
    MyContract target;

    function setUp() public {
        target = new MyContract();
    }

    function test_assertionPasses() public {
        // Register the assertion
        cl.assertion({
            adopter: address(target),
            createData: type(MyAssertion).creationCode,
            fnSelector: MyAssertion.checkInvariant.selector
        });

        // Execute a transaction - assertion runs automatically
        target.deposit{value: 1 ether}();
    }

    function test_assertionFails() public {
        cl.assertion({
            adopter: address(target),
            createData: type(MyAssertion).creationCode,
            fnSelector: MyAssertion.checkInvariant.selector
        });

        // This should revert because the assertion fails
        vm.expectRevert("Balance decreased unexpectedly");
        target.withdraw(1 ether);
    }
}
```

Run tests with:
```bash
pcl test
```

## PhEvm Cheatcodes

Access these via the `ph` instance inherited from `Credible`:

| Function | Description |
|----------|-------------|
| `forkPreTx()` | Fork to state before the transaction |
| `forkPostTx()` | Fork to state after the transaction |
| `forkPreCall(uint256 id)` | Fork to state before a specific call |
| `forkPostCall(uint256 id)` | Fork to state after a specific call |
| `load(address, bytes32)` | Load a storage slot value |
| `getLogs()` | Get all logs emitted in the transaction |
| `getCallInputs(address, bytes4)` | Get CALL inputs for target/selector |
| `getStaticCallInputs(address, bytes4)` | Get STATICCALL inputs |
| `getDelegateCallInputs(address, bytes4)` | Get DELEGATECALL inputs |
| `getAllCallInputs(address, bytes4)` | Get all call types |
| `getStateChanges(address, bytes32)` | Get state changes for a slot |
| `getAssertionAdopter()` | Get the adopter contract address |

## Trigger Types

Register triggers in your `triggers()` function:

```solidity
function triggers() external view override {
    // Trigger on any call to the adopter
    registerCallTrigger(this.myAssertion.selector);

    // Trigger on specific function call
    registerCallTrigger(this.myAssertion.selector, ITarget.transfer.selector);

    // Trigger on any storage change
    registerStorageChangeTrigger(this.myAssertion.selector);

    // Trigger on specific storage slot change
    registerStorageChangeTrigger(this.myAssertion.selector, bytes32(uint256(0)));

    // Trigger on balance change
    registerBalanceChangeTrigger(this.myAssertion.selector);
}
```

## Backtesting

Test your assertions against historical blockchain transactions to validate correctness before deployment. The backtesting framework automatically detects both direct calls AND internal/nested calls to your target contract.

### Setup

Add to your `foundry.toml`:

```toml
[profile.backtesting]
src = "src"
test = "test"
ffi = true
gas_limit = 100000000
```

### Block Range Backtesting

Test all transactions in a block range:

```solidity
import {CredibleTestWithBacktesting} from "credible-std/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "credible-std/utils/BacktestingTypes.sol";

contract MyBacktest is CredibleTestWithBacktesting {
    function testHistoricalTransactions() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: 0x1234...,           // Contract to monitor
                endBlock: 1000000,                   // End block
                blockRange: 100,                     // Number of blocks to test
                assertionCreationCode: type(MyAssertion).creationCode,
                assertionSelector: MyAssertion.check.selector,
                rpcUrl: "https://eth.llamarpc.com",
                detailedBlocks: false,               // Verbose block output
                forkByTxHash: true                   // Fork by tx hash for accurate state
            })
        );

        // Check no assertions failed
        assertEq(results.assertionFailures, 0, "Assertions failed on historical data");
    }
}
```

### Single Transaction Backtesting

Test a specific transaction by hash:

```solidity
contract MyBacktest is CredibleTestWithBacktesting {
    function testSpecificTransaction() public {
        bytes32 txHash = 0xabc123...;

        BacktestingTypes.BacktestingResults memory results = executeBacktestForTransaction(
            txHash,
            0x1234...,                              // Target contract
            type(MyAssertion).creationCode,
            MyAssertion.check.selector,
            "https://eth.llamarpc.com"
        );

        assertEq(results.assertionFailures, 0);
    }
}
```

### Running Backtests

```bash
# Run with verbose output
pcl test --ffi -vvvv --match-test testHistoricalTransactions

# Or with the backtesting profile
FOUNDRY_PROFILE=backtesting pcl test -vvvv
```

### Internal Call Detection

The backtesting framework automatically detects transactions that call your target contract internally (e.g., through a router or aggregator). It tries multiple trace APIs with automatic fallback:

1. **trace_filter** - Fastest, requires Erigon or archive node with trace API
2. **debug_traceBlockByNumber** - Slower but widely supported
3. **debug_traceTransaction** - Slowest, per-transaction tracing
4. **Direct calls only** - Fallback when no trace APIs available

Example output:
```
=== TRANSACTION DISCOVERY ===
Target: 0x1234...
Blocks: 1000000 to 1000100

[INFO] Detecting both direct calls AND internal/nested calls to target
[INFO] Trying trace APIs with automatic fallback...

[TRACE] Using trace_filter API (fastest method for internal call detection)
[TRACE] trace_filter not supported by this RPC endpoint
[TRACE] Falling back to debug_traceBlockByNumber (slower but widely supported)

=== DISCOVERY COMPLETE ===
[INFO] Detection method: debug_traceBlockByNumber
[INFO] Internal calls: ENABLED
```

### Understanding Results

The backtesting framework provides detailed categorization:

| Result | Description |
|--------|-------------|
| **Success** | Transaction passed assertion validation |
| **Skipped** | Transaction didn't trigger the assertion (selector mismatch) |
| **Assertion Failed** | Real protocol violation detected |
| **Replay Failure** | Transaction reverted before assertion could run |
| **Unknown Error** | Unexpected failure |

When an assertion fails, the framework automatically replays the transaction with full Foundry tracing enabled, showing the complete execution path for debugging.

## State Change Helpers

The `StateChanges` contract provides type-safe helpers for inspecting storage changes:

```solidity
// Get state changes as specific types
uint256[] memory uintChanges = getStateChangesUint(target, slot);
address[] memory addrChanges = getStateChangesAddress(target, slot);
bool[] memory boolChanges = getStateChangesBool(target, slot);
bytes32[] memory rawChanges = getStateChangesBytes32(target, slot);

// With mapping key support
uint256[] memory balanceChanges = getStateChangesUint(target, balancesSlot, userKey);

// With slot offset for struct fields
uint256[] memory fieldChanges = getStateChangesUint(target, structSlot, key, fieldOffset);
```

## Resources

- [Credible Layer Documentation](https://docs.phylax.systems/credible/credible-introduction)
- [Writing Assertions Guide](https://docs.phylax.systems/credible/pcl-assertion-guide)
- [Testing Assertions Guide](https://docs.phylax.systems/credible/testing-assertions)
- [API Documentation](https://phylaxsystems.github.io/credible-std)

## License

MIT
