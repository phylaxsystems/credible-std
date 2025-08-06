// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CredibleTest} from "../CredibleTest.sol";
import {Test, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BacktestingTypes} from "./BacktestingTypes.sol";
import {BacktestingUtils} from "./BacktestingUtils.sol";

/// @title Extended CredibleTest with Backtesting
/// @notice CredibleTest with built-in backtesting functionality
/// @dev Users inherit from this instead of CredibleTest directly
abstract contract CredibleTestWithBacktesting is CredibleTest, Test {
    using Strings for uint256;

    /// @notice Execute backtesting with simple interface
    /// @param targetContract Contract to test assertions against
    /// @param endBlock Latest block to test (works backwards)
    /// @param blockRange Number of blocks to test
    /// @param assertionCreationCode Bytecode for assertion contract
    /// @param assertionSelector Function selector to trigger
    /// @param rpcUrl RPC URL for blockchain access
    /// @return results Detailed backtesting results with error categorization
    function executeBacktest(
        address targetContract,
        uint256 endBlock,
        uint256 blockRange,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl
    ) public returns (BacktestingTypes.BacktestingResults memory results) {
        // Log configuration at the start
        console.log("=== BACKTESTING CONFIGURATION ===");
        console.log(string.concat("Target contract: ", Strings.toHexString(targetContract)));
        console.log(
            string.concat(
                "Block range: ",
                (endBlock > blockRange ? endBlock - blockRange + 1 : 1).toString(),
                " to ",
                endBlock.toString()
            )
        );
        console.log(string.concat("Assertion selector: ", Strings.toHexString(uint32(assertionSelector), 4)));
        console.log(string.concat("RPC URL: ", rpcUrl));
        console.log("=================================");

        console.log("=== BACKTESTING START ===");
        console.log(string.concat("Target contract: ", Strings.toHexString(targetContract)));

        uint256 startBlock = endBlock > blockRange ? endBlock - blockRange + 1 : 1;
        console.log(string.concat("Block range: ", startBlock.toString(), " to ", endBlock.toString()));

        BacktestingTypes.TransactionData[] memory transactions =
            _fetchTransactions(targetContract, startBlock, endBlock, rpcUrl);
        results.totalTransactions = transactions.length;
        console.log(string.concat("Total transactions found: ", results.totalTransactions.toString()));

        if (transactions.length == 0) {
            console.log("No transactions to process");
            console.log(string.concat("Block range: ", startBlock.toString(), " to ", endBlock.toString()));
            return results;
        }

        for (uint256 i = 0; i < transactions.length; i++) {
            BacktestingTypes.ValidationDetails memory validation =
                _validateTransaction(targetContract, assertionCreationCode, assertionSelector, rpcUrl, transactions[i]);

            if (validation.result == BacktestingTypes.ValidationResult.Success) {
                results.successfulValidations++;
                console.log(
                    string.concat(
                        "[PASS] TX ",
                        (i + 1).toString(),
                        " ",
                        BacktestingUtils.bytes32ToHex(transactions[i].hash),
                        " ",
                        BacktestingUtils.extractFunctionSelector(transactions[i].data)
                    )
                );
            } else {
                results.failedValidations++;
                _categorizeAndLogError(i, transactions[i], validation);
                _incrementErrorCounter(results, validation.result);
            }
        }

        _printDetailedResults(startBlock, endBlock, results);
        return results;
    }

    /// @notice Execute backtesting with config struct
    function executeBacktest(BacktestingTypes.BacktestingConfig memory config)
        public
        returns (BacktestingTypes.BacktestingResults memory results)
    {
        return executeBacktest(
            config.targetContract,
            config.endBlock,
            config.blockRange,
            config.assertionCreationCode,
            config.assertionSelector,
            config.rpcUrl
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
        return executeBacktest(targetContract, endBlock, blockRange, assertionCreationCode, assertionSelector, rpcUrl);
    }

    /// @notice Fetch transactions using FFI
    function _fetchTransactions(address targetContract, uint256 startBlock, uint256 endBlock, string memory rpcUrl)
        private
        returns (BacktestingTypes.TransactionData[] memory transactions)
    {
        // Build FFI command with optimized settings
        string[] memory inputs = new string[](16);
        inputs[0] = "rust-script";
        inputs[1] = "scripts/backtesting/transaction_fetcher.rs";
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

    /// @notice Validate a single transaction with detailed error categorization
    function _validateTransaction(
        address targetContract,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl,
        BacktestingTypes.TransactionData memory txData
    ) private returns (BacktestingTypes.ValidationDetails memory validation) {
        try this._forkAndValidate(targetContract, assertionCreationCode, assertionSelector, rpcUrl, txData) {
            validation.result = BacktestingTypes.ValidationResult.Success;
            validation.isProtocolViolation = false;
        } catch Error(string memory reason) {
            validation.result = BacktestingTypes.ValidationResult.AssertionFailed;
            validation.errorMessage = reason;
            validation.isProtocolViolation = true;
        } catch Panic(uint256 errorCode) {
            if (errorCode == 0x01) {
                validation.result = BacktestingTypes.ValidationResult.AssertionFailed;
                validation.errorMessage = "Assertion failed";
                validation.isProtocolViolation = true;
            } else if (errorCode == 0x11) {
                validation.result = BacktestingTypes.ValidationResult.GasLimitExceeded;
                validation.errorMessage = "Gas limit exceeded";
                validation.isProtocolViolation = false;
            } else {
                validation.result = BacktestingTypes.ValidationResult.UnknownError;
                validation.errorMessage = "Unknown panic";
                validation.isProtocolViolation = false;
            }
        } catch (bytes memory) {
            validation.result = BacktestingTypes.ValidationResult.UnknownError;
            validation.isProtocolViolation = false;
        }
    }

    /// @notice Fork and validate (external for try/catch)
    function _forkAndValidate(
        address targetContract,
        bytes memory assertionCreationCode,
        bytes4 assertionSelector,
        string memory rpcUrl,
        BacktestingTypes.TransactionData memory txData
    ) external {
        // Fork to the block before the transaction
        vm.createSelectFork(rpcUrl, txData.blockNumber - 1);
        vm.fee(0);

        // Prepare transaction sender
        vm.stopPrank();
        vm.deal(txData.from, 10 ether);

        // Setup assertion
        cl.assertion({adopter: targetContract, createData: assertionCreationCode, fnSelector: assertionSelector});

        // Execute the transaction
        vm.prank(txData.from);
        (bool callSuccess,) = txData.to.call{value: txData.value}(txData.data);
        require(callSuccess || !callSuccess, "Call completed");
    }

    /// @notice Categorize and log error details
    function _categorizeAndLogError(
        uint256 txIndex,
        BacktestingTypes.TransactionData memory txData,
        BacktestingTypes.ValidationDetails memory validation
    ) private pure {
        string memory errorType = _getErrorTypeString(validation.result);
        console.log(
            string.concat(
                "[",
                errorType,
                "] TX ",
                (txIndex + 1).toString(),
                " ",
                BacktestingUtils.bytes32ToHex(txData.hash),
                " ",
                BacktestingUtils.extractFunctionSelector(txData.data)
            )
        );

        if (bytes(validation.errorMessage).length > 0) {
            console.log(string.concat("  Error: ", validation.errorMessage));
        }

        if (validation.isProtocolViolation) {
            console.log("  !!! PROTOCOL VIOLATION DETECTED");
        }
    }

    /// @notice Increment the appropriate error counter
    function _incrementErrorCounter(
        BacktestingTypes.BacktestingResults memory results,
        BacktestingTypes.ValidationResult result
    ) private pure {
        if (result == BacktestingTypes.ValidationResult.AssertionFailed) {
            results.assertionFailures++;
        } else if (result == BacktestingTypes.ValidationResult.TransactionReverted) {
            results.transactionReverts++;
        } else if (result == BacktestingTypes.ValidationResult.ForkError) {
            results.forkErrors++;
        } else if (result == BacktestingTypes.ValidationResult.InvalidTransaction) {
            results.invalidTransactions++;
        } else if (result == BacktestingTypes.ValidationResult.GasLimitExceeded) {
            results.gasLimitExceeded++;
        } else if (result == BacktestingTypes.ValidationResult.StateMismatch) {
            results.stateMismatches++;
        } else if (result == BacktestingTypes.ValidationResult.UnknownError) {
            results.unknownErrors++;
        }
    }

    /// @notice Get human-readable error type string
    function _getErrorTypeString(BacktestingTypes.ValidationResult result) private pure returns (string memory) {
        if (result == BacktestingTypes.ValidationResult.Success) return "PASS";
        if (result == BacktestingTypes.ValidationResult.AssertionFailed) return "ASSERTION_FAIL";
        if (result == BacktestingTypes.ValidationResult.TransactionReverted) return "TX_REVERT";
        if (result == BacktestingTypes.ValidationResult.ForkError) return "FORK_ERROR";
        if (result == BacktestingTypes.ValidationResult.InvalidTransaction) return "INVALID_TX";
        if (result == BacktestingTypes.ValidationResult.GasLimitExceeded) return "GAS_LIMIT";
        if (result == BacktestingTypes.ValidationResult.StateMismatch) return "STATE_MISMATCH";
        return "UNKNOWN_ERROR";
    }

    /// @notice Print detailed results with error categorization
    function _printDetailedResults(
        uint256 startBlock,
        uint256 endBlock,
        BacktestingTypes.BacktestingResults memory results
    ) private pure {
        console.log("");
        console.log("=== DETAILED BACKTESTING RESULTS ===");
        console.log(string.concat("Block Range: ", startBlock.toString(), " - ", endBlock.toString()));
        console.log(string.concat("Total Transactions: ", results.totalTransactions.toString()));
        console.log(string.concat("Successful Validations: ", results.successfulValidations.toString()));
        console.log(string.concat("Failed Validations: ", results.failedValidations.toString()));
        console.log("");
        console.log("=== ERROR BREAKDOWN ===");
        console.log(string.concat("Protocol Violations (Assertion Failures): ", results.assertionFailures.toString()));
        console.log(string.concat("Transaction Reverts: ", results.transactionReverts.toString()));
        console.log(string.concat("Fork Errors: ", results.forkErrors.toString()));
        console.log(string.concat("Invalid Transactions: ", results.invalidTransactions.toString()));
        console.log(string.concat("Gas Limit Exceeded: ", results.gasLimitExceeded.toString()));
        console.log(string.concat("State Mismatches: ", results.stateMismatches.toString()));
        console.log(string.concat("Unknown Errors: ", results.unknownErrors.toString()));
        console.log("");

        uint256 successRate =
            results.totalTransactions > 0 ? (results.successfulValidations * 100) / results.totalTransactions : 0;
        console.log(string.concat("Success Rate: ", successRate.toString(), "%"));

        if (results.assertionFailures > 0) {
            console.log(string.concat("!!! PROTOCOL VIOLATIONS DETECTED: ", results.assertionFailures.toString()));
        }
        console.log("================================");
    }
}
