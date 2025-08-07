# Backtesting Module

Backtesting functionality for credible-std that allows you to test assertions against historical blockchain transactions.

## Overview

The backtesting module provides a simple interface to validate assertions against real blockchain transactions.

## Performance

100 blocks with a total of 175 transactions takes around 50 seconds to run.

## Quick Start

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CredibleTestWithBacktesting} from "../src/backtesting/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "../src/backtesting/BacktestingTypes.sol";
import {MyAssertion} from "../assertions/src/MyAssertion.a.sol";

contract MyBacktestingTest is CredibleTestWithBacktesting {
    function testHistoricalTransactions() public {
        // Execute backtesting with one function call
        BacktestingTypes.BacktestingResults memory results = executeBacktest({
            targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            endBlock: 31336940,
            blockRange: 20,
            assertionCreationCode: type(MyAssertion).creationCode,
            assertionSelector: MyAssertion.assertionInvariant.selector,
            rpcUrl: "https://sepolia.optimism.io"
        });

        // Check results
        assert(results.assertionFailures == 0, "Found protocol violations!");
    }
}
```

## Running Tests

You can either define the RPC in the environment variable `RPC_URL` or pass it as a parameter to the `executeBacktest` function.

```bash
# Set RPC URL environment variable
export RPC_URL="https://sepolia.optimism.io"

# Run backtesting tests
pcl test --ffi --match-test testHistoricalTransactions

# With RPC URL in the command
pcl test --ffi --match-test testHistoricalTransactions --rpc-url https://sepolia.optimism.io
```

## API Reference

### Main Function

```solidity
function executeBacktest(
    address targetContract, // Contract to test assertions against
    uint256 endBlock, // Latest block to test (works backwards)
    uint256 blockRange, // Number of blocks to test
    bytes memory assertionCreationCode, // Bytecode for assertion contract
    bytes4 assertionSelector, // Function selector to trigger
    string memory rpcUrl // RPC URL endpoint
) public returns (BacktestingTypes.BacktestingResults memory results)
```

### Configuration Struct

```solidity
struct BacktestingConfig {
    address targetContract;      // Contract to test assertions against
    uint256 endBlock;            // Latest block to test (works backwards)
    uint256 blockRange;          // Number of blocks to test
    bytes assertionCreationCode; // Bytecode for assertion contract
    bytes4 assertionSelector;    // Function selector to trigger
    string rpcUrl;               // RPC URL for blockchain access
}
```

### Results Struct

```solidity
struct BacktestingResults {
    uint256 totalTransactions;
    uint256 successfulValidations;
    uint256 failedValidations;
    uint256 errorTransactions;
    
    // Detailed error breakdown
    uint256 assertionFailures;      // Real protocol violations
    uint256 transactionReverts;     // Transaction execution failures
    uint256 forkErrors;             // Blockchain state issues
    uint256 invalidTransactions;    // Data parsing issues
    uint256 gasLimitExceeded;       // Gas-related failures
    uint256 stateMismatches;        // State consistency issues
    uint256 unknownErrors;          // Unexpected failures
}
```

## Usage Examples

### Basic Usage

```solidity
function testBasicBacktesting() public {
    BacktestingTypes.BacktestingResults memory results = executeBacktest({
        targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
        endBlock: 31336940,
        blockRange: 20,
        assertionCreationCode: type(MyAssertion).creationCode,
        assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
        rpcUrl: "https://sepolia.optimism.io"
    });

    console.log("Success rate:", (results.successfulValidations * 100) / results.totalTransactions, "%");
}
```

### Using Configuration Struct

```solidity
function setUp() public {
    config = BacktestingTypes.BacktestingConfig({
        targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
        endBlock: 31336940,
        blockRange: 20,
        assertionCreationCode: type(MyAssertion).creationCode,
        assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
        rpcUrl: "https://sepolia.optimism.io"
    });
}

function testWithConfig() public {
    BacktestingTypes.BacktestingResults memory results = executeBacktest(config);
    // Process results...
}
```

### Using Environment Variable

```solidity
function testWithEnvRPC() public {
    // Uses RPC_URL from environment
    BacktestingTypes.BacktestingResults memory results = executeBacktest({
        targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia 
        endBlock: 31336940,
        blockRange: 20,
        assertionCreationCode: type(MyAssertion).creationCode,
        assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
        // no rpcUrl needed
    });
}
```

## Error Categorization

The backtesting system provides this error categorization:

- **AssertionFailures**: Real protocol violations (most important)
- **TransactionReverts**: Expected transaction failures
- **ForkErrors**: Blockchain state access issues
- **InvalidTransactions**: Data parsing problems
- **GasLimitExceeded**: Performance issues
- **StateMismatches**: State consistency problems
- **UnknownErrors**: Unexpected failures

## Requirements

- **Rust**: For transaction fetching (rust-script)
- **RPC Endpoint**: For blockchain data access
- **Assertion Contract**: Compiled bytecode and function selector

## File Structure

```
src/backtesting/
├── BacktestingTypes.sol            # Type definitions
├── BacktestingUtils.sol            # Utility functions
├── CredibleTestWithBacktesting.sol # Main backtesting contract
└── README.md                       # This file

scripts/backtesting/
└── transaction_fetcher.rs          # Rust script for transaction fetching
```
