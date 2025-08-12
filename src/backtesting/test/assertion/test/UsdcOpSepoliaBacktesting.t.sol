// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CredibleTestWithBacktesting} from "../../../CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "../../../BacktestingTypes.sol";
import {ERC20Assertion} from "../src/ERC20Assertion.a.sol";

/// @title Simple Backtesting Test
/// @notice Demonstrates the backtesting interface
contract UsdcOpSepoliaBacktestingTest is CredibleTestWithBacktesting {
    // Configuration that can be set in setUp()
    BacktestingTypes.BacktestingConfig public config;

    /// @notice Setup backtesting configuration - automatically called by Forge!
    function setUp() public {
        // Configure your backtesting parameters here
        config = BacktestingTypes.BacktestingConfig({
            targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            endBlock: 31336940, // Known block with transfer
            blockRange: 20, // 20 blocks before
            assertionCreationCode: type(ERC20Assertion).creationCode,
            assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
            rpcUrl: "https://sepolia.optimism.io"
        });
    }

    /// @notice Test ERC20 assertion with setup configuration - ultra clean!
    function testBacktestingWithSetup() public {
        // Execute backtesting using setup configuration - one line!
        BacktestingTypes.BacktestingResults memory results = executeBacktest(config);

        // Results are automatically logged
        console.log("=== SETUP-BASED RESULTS ===");
        console.log("Total processed:", results.totalTransactions);
        console.log(
            "Success rate:",
            results.totalTransactions > 0 ? (results.successfulValidations * 100) / results.totalTransactions : 0,
            "%"
        );
    }

    /// @notice Test USDC on mainnet Sepolia
    function testMainnetSepoliaUSDC() public {
        console.log("=== MAINNET SEPOLIA USDC BACKTESTING ===");

        // Execute backtesting on mainnet Sepolia USDC
        BacktestingTypes.BacktestingResults memory results = executeBacktest({
            targetContract: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC on mainnet Sepolia
            endBlock: 8925198, // Recent block on mainnet Sepolia
            blockRange: 10, // 10 blocks before
            assertionCreationCode: type(ERC20Assertion).creationCode,
            assertionSelector: ERC20Assertion.assertionTransferInvariant.selector
        });

        // Results are automatically logged
        console.log("=== MAINNET SEPOLIA RESULTS ===");
        console.log("Total processed:", results.totalTransactions);
        console.log(
            "Success rate:",
            results.totalTransactions > 0 ? (results.successfulValidations * 100) / results.totalTransactions : 0,
            "%"
        );
    }

    /// @notice Test ERC20 assertion with the new interface
    function testSimpleERC20Backtesting() public {
        // Skip if RPC_URL not provided
        try vm.envString("RPC_URL") returns (string memory) {
            console.log("=== SIMPLE BACKTESTING DEMO ===");

            // Execute backtesting with one simple function call!
            BacktestingTypes.BacktestingResults memory results = executeBacktest({
                targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
                endBlock: 31250000, // Recent block
                blockRange: 100, // Test range
                assertionCreationCode: type(ERC20Assertion).creationCode,
                assertionSelector: ERC20Assertion.assertionTransferInvariant.selector
            });

            // Results are automatically logged, but we can also use them
            console.log("=== FINAL SUMMARY ===");
            console.log("Total processed:", results.totalTransactions);
            console.log(
                "Success rate:",
                results.totalTransactions > 0 ? (results.successfulValidations * 100) / results.totalTransactions : 0,
                "%"
            );
        } catch {
            console.log("WARNING: RPC_URL not provided, skipping backtesting test");
        }
    }

    /// @notice Test with explicit RPC URL
    function testSimpleBacktestingWithRPC() public {
        console.log("=== SIMPLE BACKTESTING WITH EXPLICIT RPC ===");

        // Execute backtesting with explicit RPC
        BacktestingTypes.BacktestingResults memory results = executeBacktest({
            targetContract: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            endBlock: 31336940, // Known block with transfer
            blockRange: 20, // 20 blocks before
            assertionCreationCode: type(ERC20Assertion).creationCode,
            assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
            rpcUrl: "https://sepolia.optimism.io"
        });

        // Demonstrate how easy it is to use the results
        if (results.totalTransactions > 0) {
            uint256 successRate = (results.successfulValidations * 100) / results.totalTransactions;
            console.log("Backtesting completed with", successRate, "% success rate");

            if (results.failedValidations > 0) {
                console.log("WARNING:", results.failedValidations, "transactions failed assertions");
            }

            if (results.assertionFailures > 0) {
                console.log("ERROR:", results.assertionFailures, "transactions had assertion failures");
            }
        } else {
            console.log("No transactions found in the specified range");
        }
    }

    /// @notice Demonstrate different assertion types
    function testMultipleAssertionTypes() public pure {
        // This demonstrates how easy it would be to test different assertions
        // (commented out since we don't have the contracts, but shows the pattern)

        /*
        // Test ERC20 transfers
        executeBacktest({
            targetContract: 0x...,
            endBlock: 31250000,
            blockRange: 100,
            assertionCreationCode: type(ERC20Assertion).creationCode,
            assertionSelector: ERC20Assertion.assertionTransferInvariant.selector
        });
        
        // Test lending protocol
        executeBacktest({
            targetContract: 0x...,
            endBlock: 31250000,
            blockRange: 100,
            assertionCreationCode: type(LendingAssertion).creationCode,
            assertionSelector: LendingAssertion.assertionDepositInvariant.selector
        });
        
        // Test DEX swaps
        executeBacktest({
            targetContract: 0x...,
            endBlock: 31250000,
            blockRange: 100,
            assertionCreationCode: type(DEXAssertion).creationCode,
            assertionSelector: DEXAssertion.assertionSwapInvariant.selector
        });
        */

        console.log("Multiple assertion types would be this easy to test!");
    }
}
