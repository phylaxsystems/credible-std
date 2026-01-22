// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CredibleTest} from "./CredibleTest.sol";
import {Test, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BacktestingTypes} from "./utils/BacktestingTypes.sol";
import {BacktestingUtils} from "./utils/BacktestingUtils.sol";

/// @title CredibleTestWithBacktesting
/// @author Phylax Systems
/// @notice Extended CredibleTest with historical transaction backtesting capabilities
/// @dev Inherit from this contract to test assertions against historical blockchain transactions.
/// Supports two modes:
/// - Block range mode: Test all transactions in a block range via `executeBacktest(config)`
/// - Single transaction mode: Test a specific transaction via `executeBacktestForTransaction(txHash, ...)`
///
/// Example:
/// ```solidity
/// contract MyBacktest is CredibleTestWithBacktesting {
///     function testHistorical() public {
///         executeBacktest(BacktestingTypes.BacktestingConfig({
///             targetContract: 0x...,
///             endBlock: 1000000,
///             blockRange: 100,
///             assertionCreationCode: type(MyAssertion).creationCode,
///             assertionSelector: MyAssertion.check.selector,
///             rpcUrl: "https://eth.llamarpc.com",
///             detailedBlocks: false,
///             forkByTxHash: true
///         }));
///     }
/// }
/// ```
abstract contract CredibleTestWithBacktesting is CredibleTest, Test {
    using Strings for uint256;

    /// @dev Cached script path to avoid repeated filesystem lookups
    string private _cachedScriptPath;

    /// @notice Execute backtesting for a single transaction by hash (overload for single tx mode)
    /// @param txHash The transaction hash to backtest
    /// @param targetContract The target contract address
    /// @param assertionCreationCode The assertion contract creation code
    /// @param assertionSelector The assertion function selector
    /// @param rpcUrl The RPC URL to use
    /// @return results The backtesting results
    function executeBacktestForTransaction(
        bytes32 txHash,
        address targetContract,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        return _executeBacktestForSingleTransaction(
            txHash, targetContract, assertionCreationCode, assertionSelector, rpcUrl
        );
    }

    /// @notice Execute backtesting with config struct (block range mode)
    function executeBacktest(BacktestingTypes.BacktestingConfig memory config)
        public
        returns (BacktestingTypes.BacktestingResults memory results)
    {
        uint256 startBlock = config.endBlock > config.blockRange ? config.endBlock - config.blockRange + 1 : 1;

        // Print configuration at the start
        console.log("==========================================");
        console.log("         BACKTESTING CONFIGURATION");
        console.log("==========================================");
        console.log(string.concat("Target Contract: ", Strings.toHexString(config.targetContract)));
        console.log(string.concat("Block Range: ", startBlock.toString(), " to ", config.endBlock.toString()));
        console.log(string.concat("Assertion Selector: ", Strings.toHexString(uint32(config.assertionSelector), 4)));
        console.log(string.concat("RPC URL: ", config.rpcUrl));
        console.log("==========================================");
        console.log("");

        BacktestingTypes.TransactionData[] memory transactions =
            _fetchTransactions(config.targetContract, startBlock, config.endBlock, config.rpcUrl);
        results.totalTransactions = transactions.length;
        results.processedTransactions = 0; // Initialize processed transactions counter
        console.log(string.concat("Total transactions found: ", results.totalTransactions.toString()));

        if (transactions.length == 0) {
            console.log("No transactions to process");
            console.log(string.concat("Block range: ", startBlock.toString(), " to ", config.endBlock.toString()));
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
                config.targetContract,
                config.assertionCreationCode,
                config.assertionSelector,
                config.rpcUrl,
                transactions[i],
                config.forkByTxHash
            );

            results.processedTransactions++;

            if (validation.result == BacktestingTypes.ValidationResult.Success) {
                results.successfulValidations++;
                console.log("[PASS] VALIDATION PASSED");
            } else if (validation.result == BacktestingTypes.ValidationResult.Skipped) {
                results.skippedTransactions++;
                console.log("[SKIP] Assertion not triggered on this transaction");
            } else if (validation.result == BacktestingTypes.ValidationResult.ReplayFailure) {
                results.replayFailures++;
                _categorizeAndLogError(validation);
            } else if (validation.result == BacktestingTypes.ValidationResult.AssertionFailed) {
                results.assertionFailures++;
                _categorizeAndLogError(validation);
                // Replay the transaction to show full trace
                console.log("");
                console.log("=== REPLAYING FAILED TRANSACTION FOR TRACE ===");
                _replayTransactionForTrace(
                    config.targetContract,
                    config.assertionCreationCode,
                    config.assertionSelector,
                    config.rpcUrl,
                    transactions[i]
                );
            } else {
                results.unknownErrors++;
                _categorizeAndLogError(validation);
            }

            // Print transaction end marker
            console.log("---");
        }

        _printDetailedResults(startBlock, config.endBlock, results);
        return results;
    }

    /// @notice Get the standard search paths for transaction_fetcher.sh
    /// @dev Override this in your test contract to add custom search paths
    /// @return Array of paths to check, in order of preference
    function _getScriptSearchPaths() internal view virtual returns (string[] memory) {
        return BacktestingUtils.getDefaultScriptSearchPaths();
    }

    /// @notice Find the transaction_fetcher.sh script path
    /// @dev Checks environment variable first, then searches common locations,
    ///      and finally uses `find` to auto-detect the script location.
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

        // Auto-detect using find command as fallback
        string memory autoDetectedPath = _autoDetectScriptPath();
        if (bytes(autoDetectedPath).length > 0) {
            _cachedScriptPath = autoDetectedPath;
            return _cachedScriptPath;
        }

        // No valid path found - provide helpful error message
        revert(
            "transaction_fetcher.sh not found. "
            "Set CREDIBLE_STD_PATH environment variable or override _getScriptSearchPaths(). "
            "Auto-detection also failed. Ensure credible-std is installed in your project."
        );
    }

    /// @notice Auto-detect the script path using find command
    /// @dev Searches the project directory for transaction_fetcher.sh
    /// @return The detected path, or empty string if not found
    function _autoDetectScriptPath() internal virtual returns (string memory) {
        // Use find to locate the script, searching common dependency directories
        // Limit depth to avoid searching too deep and improve performance
        string[] memory findCmd = new string[](3);
        findCmd[0] = "bash";
        findCmd[1] = "-c";
        findCmd[2] =
        "find . -maxdepth 6 -type f -name 'transaction_fetcher.sh' -path '*/credible-std/*' 2>/dev/null | head -1";

        try vm.ffi(findCmd) returns (bytes memory result) {
            string memory foundPath = string(result);
            // Trim whitespace/newlines
            bytes memory pathBytes = bytes(foundPath);
            uint256 len = pathBytes.length;
            while (
                len > 0 && (pathBytes[len - 1] == 0x0a || pathBytes[len - 1] == 0x0d || pathBytes[len - 1] == 0x20)
            ) {
                len--;
            }
            if (len == 0) {
                return "";
            }
            bytes memory trimmed = new bytes(len);
            for (uint256 i = 0; i < len; i++) {
                trimmed[i] = pathBytes[i];
            }
            foundPath = string(trimmed);

            // Verify the found path exists
            string[] memory testCmd = new string[](3);
            testCmd[0] = "test";
            testCmd[1] = "-f";
            testCmd[2] = foundPath;

            try vm.ffi(testCmd) {
                return foundPath;
            } catch {
                return "";
            }
        } catch {
            return "";
        }
    }

    /// @notice Fetch transactions using FFI
    /// @dev Automatically detects internal calls using trace APIs with fallback:
    ///      trace_filter -> debug_traceBlockByNumber -> debug_traceTransaction -> direct calls only
    function _fetchTransactions(address targetContract, uint256 startBlock, uint256 endBlock, string memory rpcUrl)
        private
        returns (BacktestingTypes.TransactionData[] memory transactions)
    {
        // Determine the script path relative to project root
        // The script is located at: credible-std/scripts/backtesting/transaction_fetcher.sh
        // We need to find where credible-std is installed (could be in lib/ or pvt/lib/)
        string memory scriptPath = _findScriptPath();

        // Build FFI command with optimized settings
        // Always use trace detection for internal calls (with automatic fallback)
        string[] memory inputs = new string[](17);
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
        inputs[16] = "--use-trace-filter"; // Always enabled for internal call detection

        string memory command = inputs[0];
        for (uint256 i = 1; i < inputs.length; i++) {
            command = string.concat(command, " ", inputs[i]);
        }
        console.log(string.concat("FFI command: ", command));

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

    /// @notice Execute backtesting for a single transaction specified by hash
    function _executeBacktestForSingleTransaction(
        bytes32 txHash,
        address targetContract,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl
    ) private returns (BacktestingTypes.BacktestingResults memory results) {
        // Fetch the transaction data
        BacktestingTypes.TransactionData memory txData = _fetchTransactionByHash(txHash, rpcUrl);

        // Verify the transaction was found
        if (txData.hash == bytes32(0)) {
            console.log("[ERROR] Transaction not found");
            results.totalTransactions = 0;
            return results;
        }

        results.totalTransactions = 1;
        results.processedTransactions = 0;

        // Validate the transaction
        BacktestingTypes.ValidationDetails memory validation = _validateTransaction(
            targetContract,
            assertionCreationCode,
            assertionSelector,
            rpcUrl,
            txData,
            true // Always fork by tx hash
        );

        results.processedTransactions = 1;

        if (validation.result == BacktestingTypes.ValidationResult.Success) {
            results.successfulValidations = 1;
            console.log("[PASS] Assertion passed for tx", BacktestingUtils.bytes32ToHex(txData.hash));
        } else if (validation.result == BacktestingTypes.ValidationResult.Skipped) {
            results.skippedTransactions = 1;
            console.log("[SKIP] Assertion not triggered for tx", BacktestingUtils.bytes32ToHex(txData.hash));
        } else if (validation.result == BacktestingTypes.ValidationResult.ReplayFailure) {
            results.replayFailures = 1;
            console.log("[REPLAY_FAIL]", validation.errorMessage);
        } else if (validation.result == BacktestingTypes.ValidationResult.AssertionFailed) {
            results.assertionFailures = 1;
            console.log("[FAIL] Assertion failed for tx", BacktestingUtils.bytes32ToHex(txData.hash));
            console.log("Error:", validation.errorMessage);
            console.log("");
            console.log(">>> TRANSACTION TRACE BELOW <<<");
            _replayTransactionForTrace(targetContract, assertionCreationCode, assertionSelector, rpcUrl, txData);
        } else {
            results.unknownErrors = 1;
            console.log("[ERROR]", validation.errorMessage);
        }

        return results;
    }

    /// @notice Fetch a single transaction by hash using FFI
    function _fetchTransactionByHash(bytes32 txHash, string memory rpcUrl)
        private
        returns (BacktestingTypes.TransactionData memory txData)
    {
        // Execute FFI with bash to call curl and jq
        string[] memory shellInputs = new string[](3);
        shellInputs[0] = "bash";
        shellInputs[1] = "-c";
        shellInputs[2] = string.concat(
            "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionByHash\",\"params\":[\"",
            BacktestingUtils.bytes32ToHex(txHash),
            "\"],\"id\":1}' ",
            rpcUrl,
            " | jq -r '[.result.hash, .result.from, .result.to, .result.value, .result.input, .result.blockNumber, .result.transactionIndex, .result.gasPrice] | @tsv'"
        );

        bytes memory result = vm.ffi(shellInputs);
        string memory output = string(result);

        // Parse the tab-separated output
        if (bytes(output).length == 0) {
            return txData; // Return empty struct if no result
        }

        // Parse the transaction data from the output
        // Format: hash\tfrom\tto\tvalue\tinput\tblockNumber\ttransactionIndex\tgasPrice
        txData = _parseTransactionFromTsv(output);
    }

    /// @notice Parse transaction data from tab-separated output
    function _parseTransactionFromTsv(string memory tsvLine)
        private
        pure
        returns (BacktestingTypes.TransactionData memory txData)
    {
        // Split by tab and parse each field
        bytes memory lineBytes = bytes(tsvLine);
        uint256 fieldStart = 0;
        uint256 fieldIndex = 0;
        string[] memory fields = new string[](8);

        for (uint256 i = 0; i <= lineBytes.length; i++) {
            if (i == lineBytes.length || lineBytes[i] == 0x09 || lineBytes[i] == 0x0a) {
                // Tab or newline or end of string
                if (i > fieldStart && fieldIndex < 8) {
                    bytes memory field = new bytes(i - fieldStart);
                    for (uint256 j = fieldStart; j < i; j++) {
                        field[j - fieldStart] = lineBytes[j];
                    }
                    fields[fieldIndex] = string(field);
                    fieldIndex++;
                }
                fieldStart = i + 1;
            }
        }

        // Parse fields if we have enough data
        if (fieldIndex >= 8) {
            txData.hash = BacktestingUtils.stringToBytes32(fields[0]);
            txData.from = BacktestingUtils.stringToAddress(fields[1]);
            txData.to = BacktestingUtils.stringToAddress(fields[2]);
            txData.value = BacktestingUtils.stringToUint(fields[3]);
            txData.data = BacktestingUtils.hexStringToBytes(fields[4]);
            txData.blockNumber = BacktestingUtils.stringToUint(fields[5]);
            txData.transactionIndex = BacktestingUtils.stringToUint(fields[6]);
            txData.gasPrice = BacktestingUtils.stringToUint(fields[7]);
        }
    }

    /// @notice Validate a single transaction with detailed error categorization
    function _validateTransaction(
        address targetContract,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl,
        BacktestingTypes.TransactionData memory txData,
        bool forkByTxHash
    ) private returns (BacktestingTypes.ValidationDetails memory validation) {
        // Always fork by tx hash to ensure pre-transaction state; block forks are post-state.
        if (!forkByTxHash) {
            // Keep the flag for compatibility, but avoid unsafe post-state replays.
        }
        vm.createSelectFork(rpcUrl, txData.hash);

        // Prepare transaction sender
        vm.stopPrank();

        // Setup assertion
        cl.assertion({adopter: targetContract, createData: assertionCreationCode, fnSelector: assertionSelector});

        // Execute the transaction
        uint256 gasPrice = txData.gasPrice;
        if (txData.maxFeePerGas > 0) {
            gasPrice = txData.maxFeePerGas;
        }
        if (gasPrice > 0) {
            vm.txGasPrice(gasPrice);
        }

        // Cap basefee to avoid fork replay failures when the tx gas limit defaults to 2^24.
        uint256 defaultGasLimit = 1 << 24;
        uint256 effectiveGasLimit = txData.gasLimit > defaultGasLimit ? txData.gasLimit : defaultGasLimit;
        uint256 maxAffordableBasefee = txData.from.balance / effectiveGasLimit;
        if (block.basefee > maxAffordableBasefee) {
            vm.fee(maxAffordableBasefee);
        }

        vm.prank(txData.from, txData.from);
        bool callSuccess;
        bytes memory returnData;
        if (txData.gasLimit > 0) {
            (callSuccess, returnData) = txData.to.call{value: txData.value, gas: txData.gasLimit}(txData.data);
        } else {
            (callSuccess, returnData) = txData.to.call{value: txData.value}(txData.data);
        }
        console.log(string.concat("Transaction status: ", callSuccess ? "Success" : "Failure"));

        if (callSuccess) {
            // Transaction succeeded - assertion passed
            validation.result = BacktestingTypes.ValidationResult.Success;
            validation.isProtocolViolation = false;
        } else {
            // Transaction reverted - categorize the error
            string memory revertReason = BacktestingUtils.decodeRevertReason(returnData);

            if (BacktestingUtils.startsWith(revertReason, "Mock Transaction Reverted:")) {
                // Transaction reverted before assertions could execute (prestate/context issues)
                validation.result = BacktestingTypes.ValidationResult.ReplayFailure;
                validation.errorMessage = revertReason;
                validation.isProtocolViolation = false;
            } else if (BacktestingUtils.startsWith(revertReason, "Expected 1 assertion to be executed, but 0")) {
                // Transaction succeeded but didn't trigger the monitored function selector
                validation.result = BacktestingTypes.ValidationResult.Skipped;
                validation.errorMessage = "Function selector not triggered by this transaction";
                validation.isProtocolViolation = false;
            } else if (BacktestingUtils.startsWith(revertReason, "Assertion Executor Error: ForkTxExecutionError")) {
                // Replay failed before assertion execution (e.g., insufficient funds for max fee)
                validation.result = BacktestingTypes.ValidationResult.ReplayFailure;
                validation.errorMessage = revertReason;
                validation.isProtocolViolation = false;
            } else {
                // Actual assertion failure (protocol violation)
                validation.result = BacktestingTypes.ValidationResult.AssertionFailed;
                validation.errorMessage = revertReason;
                validation.isProtocolViolation = true;
            }
        }
    }

    /// @notice Replay a failed transaction to show the full execution trace
    /// @dev Forks to state before the tx and makes a raw call so Foundry prints the full trace
    function _replayTransactionForTrace(
        address, // targetContract - unused, kept for interface compatibility
        bytes memory, // assertionCreationCode - unused
        bytes4, // assertionSelector - unused
        string memory rpcUrl,
        BacktestingTypes.TransactionData memory txData
    ) private {
        // Fork at the transaction hash - this gives us the state BEFORE this transaction
        vm.createSelectFork(rpcUrl, txData.hash);
        vm.stopPrank();

        // Make the raw call as the original sender - Foundry will trace this
        vm.prank(txData.from, txData.from);
        txData.to.call{value: txData.value}(txData.data);
    }

    /// @notice Categorize and log error details
    function _categorizeAndLogError(BacktestingTypes.ValidationDetails memory validation) private pure {
        string memory errorType = BacktestingUtils.getErrorTypeString(validation.result);
        console.log(string.concat("[", errorType, "] ", validation.errorMessage));
    }

    /// @notice Print detailed results with error categorization
    function _printDetailedResults(
        uint256 startBlock,
        uint256 endBlock,
        BacktestingTypes.BacktestingResults memory results
    ) private pure {
        uint256 failedValidations =
            results.assertionFailures + results.replayFailures + results.unknownErrors;

        console.log("");
        console.log("==========================================");
        console.log("           BACKTESTING SUMMARY");
        console.log("==========================================");
        console.log(string.concat("Block Range: ", startBlock.toString(), " - ", endBlock.toString()));
        console.log(string.concat("Total Transactions: ", results.totalTransactions.toString()));
        console.log(string.concat("Processed Transactions: ", results.processedTransactions.toString()));
        console.log(string.concat("Successful Validations: ", results.successfulValidations.toString()));
        console.log(string.concat("Skipped Transactions: ", results.skippedTransactions.toString()));
        console.log(string.concat("Failed Validations: ", failedValidations.toString()));

        if (failedValidations > 0) {
            console.log("");
            console.log("=== ERROR BREAKDOWN ===");
            console.log(
                string.concat("Protocol Violations (Assertion Failures): ", results.assertionFailures.toString())
            );
            if (results.replayFailures > 0) {
                console.log(
                    string.concat("Replay Failures (Tx reverted before assertion): ", results.replayFailures.toString())
                );
            }
            if (results.unknownErrors > 0) {
                console.log(string.concat("Unknown Errors: ", results.unknownErrors.toString()));
            }
        }
        console.log("");

        // Calculate success rate excluding skipped transactions
        uint256 validatedTransactions = results.successfulValidations + failedValidations;
        uint256 successRate =
            validatedTransactions > 0 ? (results.successfulValidations * 100) / validatedTransactions : 0;
        console.log(string.concat("Success Rate: ", successRate.toString(), "%"));

        if (results.assertionFailures > 0) {
            console.log(string.concat("!!! PROTOCOL VIOLATIONS DETECTED: ", results.assertionFailures.toString()));
        }
        console.log("================================");
    }
}
