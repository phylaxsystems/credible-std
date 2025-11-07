// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CredibleTest} from "./CredibleTest.sol";
import {Test, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BacktestingTypes} from "./utils/BacktestingTypes.sol";
import {BacktestingUtils} from "./utils/BacktestingUtils.sol";

/// @title Extended CredibleTest with Backtesting
/// @notice CredibleTest with built-in backtesting functionality
/// @dev Users inherit from this instead of CredibleTest directly
abstract contract CredibleTestWithBacktesting is CredibleTest, Test {
    using Strings for uint256;

    // Cached script path to avoid repeated lookups
    string private _cachedScriptPath;

    /// @notice Execute backtesting with detailed logging
    /// @param useTxHashFork If true, forks at exact transaction state (slow but accurate).
    ///                      If false, forks at block start (fast but may have state differences).
    ///                      Default: false. Use true only when investigating specific failures.
    function executeBacktest(
        address targetContract,
        uint256 endBlock,
        uint256 blockRange,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl,
        bool detailedBlocks,
        bool useTxHashFork
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        uint256 startBlock = endBlock > blockRange ? endBlock - blockRange + 1 : 1;

        // Print configuration at the start
        console.log("==========================================");
        console.log("         BACKTESTING CONFIGURATION");
        console.log("==========================================");
        console.log(string.concat("Target Contract: ", Strings.toHexString(targetContract)));
        console.log(string.concat("Block Range: ", startBlock.toString(), " to ", endBlock.toString()));
        console.log(string.concat("Assertion Selector: ", Strings.toHexString(uint32(assertionSelector), 4)));
        console.log(string.concat("RPC URL: ", rpcUrl));
        console.log("==========================================");
        console.log("");

        BacktestingTypes.TransactionData[] memory transactions =
            _fetchTransactions(targetContract, startBlock, endBlock, rpcUrl);
        results.totalTransactions = transactions.length;
        results.processedTransactions = 0; // Initialize processed transactions counter
        console.log(string.concat("Total transactions found: ", results.totalTransactions.toString()));

        if (transactions.length == 0) {
            console.log("No transactions to process");
            console.log(string.concat("Block range: ", startBlock.toString(), " to ", endBlock.toString()));
            return results;
        }

        for (uint256 i = 0; i < transactions.length; i++) {
            // Print transaction start marker
            console.log("");
            console.log(string.concat("=== TRANSACTION ", (i + 1).toString(), " ==="));
            console.log(string.concat("Hash: ", BacktestingUtils.bytes32ToHex(transactions[i].hash)));
            console.log(string.concat("Function: ", BacktestingUtils.extractFunctionSelector(transactions[i].data)));
            console.log("---");

            BacktestingTypes.ValidationDetails memory validation = _validateTransaction(
                targetContract, assertionCreationCode, assertionSelector, rpcUrl, transactions[i], useTxHashFork
            );

            if (validation.result == BacktestingTypes.ValidationResult.Success) {
                // This transaction was successfully validated
                results.processedTransactions++;
                results.successfulValidations++;
                console.log("[PASS] VALIDATION PASSED");
            } else if (validation.result == BacktestingTypes.ValidationResult.Skipped) {
                // This transaction didn't trigger the assertion, so skip it
                results.processedTransactions++;
                results.successfulValidations++;
                console.log("[SKIP] Assertion not triggered on this transaction");
            } else {
                // This transaction failed validation
                results.processedTransactions++;
                results.failedValidations++;
                _categorizeAndLogError(validation);
                _incrementErrorCounter(results, validation.result);
            }

            // Print transaction end marker
            console.log("---");
        }

        // Print formatted block summaries from bash if detailed blocks enabled
        if (detailedBlocks) {
            _printFormattedBlockSummaries(targetContract, startBlock, endBlock, rpcUrl);
        }

        _printDetailedResults(startBlock, endBlock, results);
        return results;
    }

    /// @notice Backward compatible wrapper without detailedBlocks and useTxHashFork parameters
    function executeBacktest(
        address targetContract,
        uint256 endBlock,
        uint256 blockRange,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        return executeBacktest(
            targetContract, endBlock, blockRange, assertionCreationCode, assertionSelector, rpcUrl, false, false
        );
    }

    /// @notice Backward compatible wrapper without useTxHashFork parameter
    function executeBacktest(
        address targetContract,
        uint256 endBlock,
        uint256 blockRange,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl,
        bool detailedBlocks
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        return executeBacktest(
            targetContract,
            endBlock,
            blockRange,
            assertionCreationCode,
            assertionSelector,
            rpcUrl,
            detailedBlocks,
            false
        );
    }

    /// @notice Execute backtesting with config struct
    function executeBacktest(
        BacktestingTypes.BacktestingConfig memory config
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        return executeBacktest(
            config.targetContract,
            config.endBlock,
            config.blockRange,
            config.assertionCreationCode,
            config.assertionSelector,
            config.rpcUrl,
            false,
            false
        );
    }

    /// @notice Convenience function with RPC_URL from environment
    function executeBacktest(
        address targetContract,
        uint256 endBlock,
        uint256 blockRange,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        string memory rpcUrl = vm.envString("RPC_URL");
        return executeBacktest(
            targetContract, endBlock, blockRange, assertionCreationCode, assertionSelector, rpcUrl, false, false
        );
    }

    /// @notice Get the standard search paths for transaction_fetcher.sh
    /// @dev Override this in your test contract to add custom search paths
    /// @return Array of paths to check, in order of preference
    function _getScriptSearchPaths() internal view virtual returns (string[] memory) {
        return BacktestingUtils.getDefaultScriptSearchPaths();
    }

    /// @notice Find the transaction_fetcher.sh script path
    /// @dev Checks environment variable first, then searches common locations
    ///      Override _getScriptSearchPaths() to customize search locations
    /// @return The path to transaction_fetcher.sh
    function _findScriptPath() internal virtual returns (string memory) {
        // Return cached path if already found
        if (bytes(_cachedScriptPath).length > 0) {
            return _cachedScriptPath;
        }

        // Check for environment variable override first
        try vm.envString("CREDIBLE_STD_PATH") returns (string memory envPath) {
            if (bytes(envPath).length > 0) {
                _cachedScriptPath = string.concat(envPath, "/scripts/backtesting/transaction_fetcher.sh");
                return _cachedScriptPath;
            }
        } catch {
            // Environment variable not set, continue with search
        }

        // Search standard locations
        string[] memory testPaths = _getScriptSearchPaths();
        for (uint256 i = 0; i < testPaths.length; i++) {
            string[] memory testCmd = new string[](3);
            testCmd[0] = "test";
            testCmd[1] = "-f";
            testCmd[2] = testPaths[i];

            try vm.ffi(testCmd) {
                // File exists, cache and return this path
                _cachedScriptPath = testPaths[i];
                return _cachedScriptPath;
            } catch {
                // File doesn't exist, try next path
                continue;
            }
        }

        // No valid path found - provide helpful error message
        revert(
            "transaction_fetcher.sh not found. "
            "Set CREDIBLE_STD_PATH environment variable or override _getScriptSearchPaths(). "
            "Standard locations checked: lib/credible-std/..., dependencies/credible-std/..., ../credible-std/..."
        );
    }

    /// @notice Fetch transactions using FFI
    function _fetchTransactions(
        address targetContract,
        uint256 startBlock,
        uint256 endBlock,
        string memory rpcUrl
    ) private returns (BacktestingTypes.TransactionData[] memory transactions) {
        // Determine the script path relative to project root
        // The script is located at: credible-std/scripts/backtesting/transaction_fetcher.sh
        // We need to find where credible-std is installed (could be in lib/ or pvt/lib/)
        string memory scriptPath = _findScriptPath();

        // Build FFI command with optimized settings
        string[] memory inputs = new string[](16);
        inputs[0] = "bash";
        inputs[1] = scriptPath;
        inputs[2] = "--rpc-url";
        inputs[3] = rpcUrl;
        inputs[4] = "--target-contract";
        inputs[5] = Strings.toHexString(targetContract);
        inputs[6] = "--start-block";
        inputs[7] = startBlock.toString();
        inputs[8] = "--end-block";
        inputs[9] = endBlock.toString();
        inputs[10] = "--batch-size";
        inputs[11] = "20"; // Optimized batch size based on performance tests
        inputs[12] = "--max-concurrent";
        inputs[13] = "10"; // Optimized concurrency based on performance tests
        inputs[14] = "--output-format";
        inputs[15] = "simple";

        // Execute FFI
        bytes memory result = vm.ffi(inputs);
        string memory output = string(result);
        // Parse transactions
        string memory dataLine = BacktestingUtils.extractDataLine(output);

        if (bytes(dataLine).length == 0 || keccak256(bytes(dataLine)) == keccak256(bytes("0"))) {
            return new BacktestingTypes.TransactionData[](0);
        }

        // Parse all transactions from the data line
        transactions = BacktestingUtils.parseMultipleTransactions(dataLine);
    }

    /// @notice Fetch transactions with raw FFI output (for detailed blocks)
    function _fetchTransactionsRaw(
        address targetContract,
        uint256 startBlock,
        uint256 endBlock,
        string memory rpcUrl,
        bool withDetailedBlocks
    ) private returns (bytes memory) {
        string memory scriptPath = _findScriptPath();

        uint256 inputSize = withDetailedBlocks ? 17 : 16;
        string[] memory inputs = new string[](inputSize);
        inputs[0] = "bash";
        inputs[1] = scriptPath;
        inputs[2] = "--rpc-url";
        inputs[3] = rpcUrl;
        inputs[4] = "--target-contract";
        inputs[5] = Strings.toHexString(targetContract);
        inputs[6] = "--start-block";
        inputs[7] = startBlock.toString();
        inputs[8] = "--end-block";
        inputs[9] = endBlock.toString();
        inputs[10] = "--batch-size";
        inputs[11] = "20";
        inputs[12] = "--max-concurrent";
        inputs[13] = "10";
        inputs[14] = "--output-format";
        inputs[15] = "simple";
        if (withDetailedBlocks) {
            inputs[16] = "--detailed-blocks";
        }

        return vm.ffi(inputs);
    }

    /// @notice Parse transactions from FFI output
    function _parseTransactionsFromOutput(
        bytes memory ffiOutput
    ) private view returns (BacktestingTypes.TransactionData[] memory) {
        string memory output = string(ffiOutput);
        string memory dataLine = BacktestingUtils.extractDataLine(output);

        if (bytes(dataLine).length == 0 || keccak256(bytes(dataLine)) == keccak256(bytes("0"))) {
            return new BacktestingTypes.TransactionData[](0);
        }

        return BacktestingUtils.parseMultipleTransactions(dataLine);
    }

    /// @notice Print formatted block summaries from bash output
    function _printFormattedBlockSummaries(
        address targetContract,
        uint256 startBlock,
        uint256 endBlock,
        string memory rpcUrl
    ) private {
        // Fetch output with detailed blocks flag
        bytes memory ffiOutput = _fetchTransactionsRaw(targetContract, startBlock, endBlock, rpcUrl, true);
        string memory output = string(ffiOutput);
        bytes memory outputBytes = bytes(output);

        // Find "BLOCK_SUMMARY_FORMATTED:START"
        bytes memory startMarker = bytes("BLOCK_SUMMARY_FORMATTED:START");
        uint256 startPos = 0;
        bool foundStart = false;

        for (uint256 i = 0; i <= outputBytes.length - startMarker.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < startMarker.length; j++) {
                if (outputBytes[i + j] != startMarker[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                startPos = i + startMarker.length + 1; // +1 to skip newline
                foundStart = true;
                break;
            }
        }

        if (!foundStart) return;

        // Find "BLOCK_SUMMARY_FORMATTED:END"
        bytes memory endMarker = bytes("BLOCK_SUMMARY_FORMATTED:END");
        uint256 endPos = 0;
        bool foundEnd = false;

        for (uint256 i = startPos; i <= outputBytes.length - endMarker.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < endMarker.length; j++) {
                if (outputBytes[i + j] != endMarker[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                endPos = i;
                foundEnd = true;
                break;
            }
        }

        if (!foundEnd) return;

        // Print each line between markers
        console.log("==========================================");
        console.log("           BLOCK SUMMARIES");
        console.log("==========================================");

        uint256 lineStart = startPos;
        for (uint256 i = startPos; i < endPos; i++) {
            if (outputBytes[i] == bytes1("\n") || i == endPos - 1) {
                // Found end of line or end of content
                uint256 lineEnd = (i == endPos - 1) ? i + 1 : i;
                uint256 lineLength = lineEnd - lineStart;

                if (lineLength > 0) {
                    // Extract and print the line
                    bytes memory lineBytes = new bytes(lineLength);
                    for (uint256 j = 0; j < lineLength; j++) {
                        lineBytes[j] = outputBytes[lineStart + j];
                    }
                    console.log(string(lineBytes));
                }

                lineStart = i + 1; // Start of next line
            }
        }

        console.log("==========================================");
    }

    /// @notice Validate a single transaction with detailed error categorization
    function _validateTransaction(
        address targetContract,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl,
        BacktestingTypes.TransactionData memory txData,
        bool useTxHashFork
    ) private returns (BacktestingTypes.ValidationDetails memory validation) {
        // Choose fork strategy based on flag
        if (useTxHashFork) {
            // Slow but accurate: fork at exact transaction state
            // Replays all prior transactions in the block
            vm.createSelectFork(rpcUrl, txData.hash);
        } else {
            // Fast: fork at start of block
            // State is at beginning of block, before any transactions
            vm.createSelectFork(rpcUrl, txData.blockNumber);
        }

        // Prepare transaction sender
        vm.stopPrank();
        vm.deal(txData.from, 10 ether);

        // Setup assertion
        cl.assertion({adopter: targetContract, createData: assertionCreationCode, fnSelector: assertionSelector});

        // Execute the transaction
        vm.prank(txData.from, txData.from);
        (bool callSuccess, bytes memory returnData) = txData.to.call{value: txData.value}(txData.data);

        string memory revertReason = BacktestingUtils.decodeRevertReason(returnData);

        if (callSuccess) {
            validation.result = BacktestingTypes.ValidationResult.Success;
            validation.isProtocolViolation = false;
        } else if (
            keccak256(bytes("Expected 1 assertion to be executed, but 0 were executed."))
                == keccak256(bytes(revertReason))
        ) {
            // This transaction doesn't trigger the assertion, so we should skip it
            // The assertion testing interface reverts if a transaction to the assertion adopter doesn't trigger the
            // assertion We have to handle this specific case, by matching the revert reason.
            validation.result = BacktestingTypes.ValidationResult.Skipped;
            validation.errorMessage = revertReason;
            validation.isProtocolViolation = false;
        } else {
            validation.result = BacktestingTypes.ValidationResult.AssertionFailed;
            validation.errorMessage = revertReason;
            validation.isProtocolViolation = true;
        }
    }

    /// @notice Categorize and log error details
    function _categorizeAndLogError(
        BacktestingTypes.ValidationDetails memory validation
    ) private view {
        string memory errorType = BacktestingUtils.getErrorTypeString(validation.result);
        console.log(string.concat("[", errorType, "] VALIDATION FAILED"));

        // Note: Revert reason is already printed by the credible framework
        // so we don't print it again here to avoid duplication
    }

    /// @notice Increment the appropriate error counter
    function _incrementErrorCounter(
        BacktestingTypes.BacktestingResults memory results,
        BacktestingTypes.ValidationResult result
    ) private pure {
        if (result == BacktestingTypes.ValidationResult.AssertionFailed) {
            results.assertionFailures++;
        } else if (result == BacktestingTypes.ValidationResult.UnknownError) {
            results.unknownErrors++;
        }
    }

    /// @notice Print detailed results with error categorization
    function _printDetailedResults(
        uint256 startBlock,
        uint256 endBlock,
        BacktestingTypes.BacktestingResults memory results
    ) private view {
        console.log("");
        console.log("==========================================");
        console.log("           BACKTESTING SUMMARY");
        console.log("==========================================");
        console.log(string.concat("Block Range: ", startBlock.toString(), " - ", endBlock.toString()));
        console.log(string.concat("Total Transactions: ", results.totalTransactions.toString()));
        console.log(string.concat("Processed Transactions: ", results.processedTransactions.toString()));
        console.log(string.concat("Successful Validations: ", results.successfulValidations.toString()));
        console.log(string.concat("Failed Validations: ", results.failedValidations.toString()));

        if (results.failedValidations > 0) {
            console.log("");
            console.log("=== ERROR BREAKDOWN ===");
            console.log(
                string.concat("Protocol Violations (Assertion Failures): ", results.assertionFailures.toString())
            );
            console.log(string.concat("Unknown Errors: ", results.unknownErrors.toString()));
        }
        console.log("");

        uint256 successRate = results.processedTransactions > 0
            ? (results.successfulValidations * 100) / results.processedTransactions
            : 0;
        console.log(string.concat("Success Rate: ", successRate.toString(), "%"));

        if (results.assertionFailures > 0) {
            console.log(string.concat("!!! PROTOCOL VIOLATIONS DETECTED: ", results.assertionFailures.toString()));
        }
        console.log("================================");
    }
}
