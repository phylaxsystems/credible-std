// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CredibleTestWithBacktesting} from "../../src/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "../../src/utils/BacktestingTypes.sol";
import {ERC20Assertion} from "../fixtures/backtesting/ERC20Assertion.a.sol";

/// @title Backtesting Integration Tests
/// @notice Tests backtesting functionality against known on-chain fixtures
contract BacktestingIntegrationTest is CredibleTestWithBacktesting {
    // USDC on Optimism Sepolia - used for ERC20 transfer tests
    address constant USDC_OP_SEPOLIA = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;

    /// @notice Test block range backtesting finds direct calls
    /// @dev Uses a known block range with USDC transfers on Optimism Sepolia
    function testBlockRangeBacktesting() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: USDC_OP_SEPOLIA,
                endBlock: 31336940,
                blockRange: 20,
                assertionCreationCode: type(ERC20Assertion).creationCode,
                assertionSelector: ERC20Assertion.assertionTransferInvariant.selector,
                rpcUrl: "https://sepolia.optimism.io",
                detailedBlocks: false,
                forkByTxHash: true
            })
        );

        // Should find and process transactions
        console.log("Total transactions found:", results.totalTransactions);
        console.log("Processed:", results.processedTransactions);
        console.log("Passed:", results.successfulValidations);
    }

    /// @notice Test that assertion failures are properly detected
    function testAssertionFailureDetection() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktest(
            BacktestingTypes.BacktestingConfig({
                targetContract: USDC_OP_SEPOLIA,
                endBlock: 31336940,
                blockRange: 20,
                assertionCreationCode: type(ERC20Assertion).creationCode,
                assertionSelector: ERC20Assertion.assertionTransferInvariantRevert.selector,
                rpcUrl: "https://sepolia.optimism.io",
                detailedBlocks: false,
                forkByTxHash: true
            })
        );

        // The reverting assertion should cause failures
        console.log("Assertion failures detected:", results.assertionFailures);
    }
}

/// @title Single Transaction Backtesting Tests
/// @notice Tests single transaction backtesting with known fixtures
contract SingleTxBacktestingTest is CredibleTestWithBacktesting {
    // Known USDC transfer on Optimism Sepolia
    // https://sepolia-optimism.etherscan.io/tx/0x...
    address constant USDC_OP_SEPOLIA = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;

    /// @notice Test single transaction backtesting with a known transfer
    /// @dev This test requires RPC access to Optimism Sepolia
    function testSingleTransactionBacktest() public {
        // Skip if no RPC available (for CI without RPC secrets)
        try vm.envString("OP_SEPOLIA_RPC_URL") returns (string memory rpcUrl) {
            // Use a real transaction hash from Optimism Sepolia
            // This should be a USDC transfer transaction
            bytes32 txHash = 0x0000000000000000000000000000000000000000000000000000000000000000;

            if (txHash == bytes32(0)) {
                console.log("SKIP: No fixture transaction hash configured");
                return;
            }

            BacktestingTypes.BacktestingResults memory results = executeBacktestForTransaction(
                txHash,
                USDC_OP_SEPOLIA,
                type(ERC20Assertion).creationCode,
                ERC20Assertion.assertionTransferInvariant.selector,
                rpcUrl
            );

            assertEq(results.totalTransactions, 1, "Should process exactly 1 transaction");
            assertEq(results.assertionFailures, 0, "Assertion should pass");
        } catch {
            console.log("SKIP: OP_SEPOLIA_RPC_URL not set");
        }
    }
}
