// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Backtesting Types
/// @notice Minimal type definitions for backtesting
library BacktestingTypes {
    /// @notice Validation result categories for detailed error analysis
    enum ValidationResult {
        Success, // Transaction passed all assertions
        Skipped, // Transaction not expected to trigger the assertion
        AssertionFailed, // Assertion logic failed (actual protocol violation)
        UnknownError // Unexpected error during validation

    }

    /// @notice Transaction data from blockchain
    struct TransactionData {
        bytes32 hash;
        address from;
        address to;
        uint256 value;
        bytes data;
        uint256 blockNumber;
        uint256 transactionIndex;
        uint256 gasPrice;
    }

    /// @notice Detailed validation result with error information
    struct ValidationDetails {
        ValidationResult result;
        string errorMessage;
        bool isProtocolViolation;
    }

    /// @notice Configuration for backtesting runs
    struct BacktestingConfig {
        address targetContract;
        uint256 endBlock;
        uint256 blockRange;
        bytes assertionCreationCode;
        bytes4 assertionSelector;
        string rpcUrl;
    }

    /// @notice Enhanced backtesting results with detailed categorization
    struct BacktestingResults {
        uint256 totalTransactions;
        uint256 processedTransactions; // Transactions that were actually validated (excluding skipped)
        uint256 successfulValidations;
        uint256 failedValidations;
        uint256 assertionFailures; // Real protocol violations
        uint256 unknownErrors; // Unexpected failures
    }
}
