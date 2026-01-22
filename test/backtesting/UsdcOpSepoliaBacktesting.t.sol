// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CredibleTestWithBacktesting} from "../../src/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "../../src/utils/BacktestingTypes.sol";
import {ERC20Assertion} from "../fixtures/backtesting/ERC20Assertion.a.sol";

/// @title Simple Backtesting Test
/// @notice Demonstrates the backtesting interface
contract UsdcOpSepoliaBacktestingTest is CredibleTestWithBacktesting {
    // Configuration that can be set in setUp()
    BacktestingTypes.BacktestingConfig public config;

    /// @notice Setup backtesting configuration struct
    function setUp() public {
        // Configure your backtesting parameters here
        config = BacktestingTypes.BacktestingConfig({
            targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            endBlock: 31336940, // Known block with transfer
            blockRange: 20, // 20 blocks before
            assertionCreationCode: type(ERC20Assertion).creationCode,
            assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
            rpcUrl: "https://sepolia.optimism.io",
            detailedBlocks: false,
            useTraceFilter: false,
            forkByTxHash: false
        });
    }

    /// @notice Test ERC20 assertion with setup configuration
    function testBacktestingWithSetup() public {
        // Execute backtesting using setUp() configuration
        executeBacktest(config);
    }

    /// @notice Test USDC on mainnet Sepolia
    function testMainnetSepoliaUSDC() public {
        console.log("=== MAINNET SEPOLIA USDC BACKTESTING ===");

        // Execute backtesting on mainnet Sepolia USDC
        executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC on mainnet Sepolia
                endBlock: 8925198, // Fairly recent block on mainnet Sepolia
                blockRange: 10, // 10 blocks before
                assertionCreationCode: type(ERC20Assertion).creationCode,
                assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
                rpcUrl: vm.envString("MAINNET_SEPOLIA_RPC_URL"),
                detailedBlocks: false,
                useTraceFilter: false,
                forkByTxHash: false
            })
        );
    }

    /// @notice Test ERC20 assertion with rpc env variable
    function testSimpleERC20Backtesting() public {
        // Skip if RPC_URL not provided
        try vm.envString("RPC_URL") returns (string memory rpcUrl) {
            console.log("=== SIMPLE BACKTESTING DEMO ===");

            executeBacktest(
                BacktestingTypes.BacktestingConfig({
                    targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
                    endBlock: 31250000, // Recent block
                    blockRange: 100, // Test range
                    assertionCreationCode: type(ERC20Assertion).creationCode,
                    assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
                    rpcUrl: rpcUrl,
                    detailedBlocks: false,
                    useTraceFilter: false,
                    forkByTxHash: false
                })
            );
        } catch {
            console.log("WARNING: RPC_URL not provided, skipping backtesting test");
        }
    }

    /// @notice Test with explicit RPC URL
    function testSimpleBacktestingWithRPC() public {
        console.log("=== SIMPLE BACKTESTING WITH EXPLICIT RPC ===");

        executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
                endBlock: 31336940, // Known block with transfer
                blockRange: 20, // 20 blocks before
                assertionCreationCode: type(ERC20Assertion).creationCode,
                assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
                rpcUrl: "https://sepolia.optimism.io",
                detailedBlocks: false,
                useTraceFilter: false,
                forkByTxHash: false
            })
        );
    }

    function testRevertingAssertion() public {
        executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
                endBlock: 31336940, // Known block with transfer
                blockRange: 20, // 20 blocks before
                assertionCreationCode: type(ERC20Assertion).creationCode,
                assertionSelector: ERC20Assertion.assertionTransferInvariantRevert.selector,
                rpcUrl: "https://sepolia.optimism.io",
                detailedBlocks: false,
                useTraceFilter: false,
                forkByTxHash: false
            })
        );
    }

    /// @notice Test single transaction backtest using the convenience function
    function testSingleTransactionBacktest() public {
        console.log("=== SINGLE TRANSACTION BACKTESTING ===");

        // Example transaction hash (use a real hash from your network)
        bytes32 txHash = 0xb97da7e0c1bc3e8a99d6dbfb1b6d97f6a9c12f0e5d8f4c6a3b2e1d0c9f8a7b6c;

        // Use the convenience function to backtest a specific transaction
        executeBacktestForTransaction(
            txHash,
            0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            type(ERC20Assertion).creationCode,
            ERC20Assertion.assertionTransferInvariant.selector,
            "https://sepolia.optimism.io"
        );
    }

    /// @notice Test single transaction backtest - alternative example
    function testSingleTransactionBacktestWithConfig() public {
        console.log("=== SINGLE TRANSACTION BACKTESTING (ALTERNATIVE) ===");

        // Example transaction hash (use a real hash from your network)
        bytes32 txHash = 0xb97da7e0c1bc3e8a99d6dbfb1b6d97f6a9c12f0e5d8f4c6a3b2e1d0c9f8a7b6c;

        // Use the convenience function - this is the only way to backtest a single transaction
        // The config struct is for block range backtesting only
        executeBacktestForTransaction(
            txHash,
            0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            type(ERC20Assertion).creationCode,
            ERC20Assertion.assertionTransferInvariant.selector,
            "https://sepolia.optimism.io"
        );
    }
}
