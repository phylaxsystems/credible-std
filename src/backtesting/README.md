# Backtesting Module

Backtesting functionality for credible-std that allows you to test assertions against historical blockchain transactions.

## Overview

The backtesting module provides a simple interface to validate assertions against real blockchain transactions.

## Performance

100 blocks with a total of 175 transactions takes around 50 seconds to run. (depending on internet speed)

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
