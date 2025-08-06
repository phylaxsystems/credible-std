// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Backtesting Types
/// @notice Minimal type definitions for backtesting
library BacktestingTypes {
    /// @notice Validation result categories for detailed error analysis
    enum ValidationResult {
        Success, // Transaction passed all assertions
        AssertionFailed, // Assertion logic failed (actual protocol violation)
        TransactionReverted, // Transaction reverted during execution
        ForkError, // Failed to fork blockchain state
        InvalidTransaction, // Transaction data parsing or validation failed
        GasLimitExceeded, // Transaction exceeded gas limit
        StateMismatch, // Forked state doesn't match expected
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
        string errorMessage; // Human-readable error description
        bytes errorData; // Raw error data for debugging
        uint256 gasUsed; // Gas used by the transaction
        bool isProtocolViolation; // Whether this represents a real protocol issue
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
        uint256 successfulValidations;
        uint256 failedValidations;
        uint256 errorTransactions;
        // Detailed breakdown by error type
        uint256 assertionFailures; // Real protocol violations
        uint256 transactionReverts; // Transaction execution failures
        uint256 forkErrors; // Blockchain state issues
        uint256 invalidTransactions; // Data parsing issues
        uint256 gasLimitExceeded; // Gas-related failures
        uint256 stateMismatches; // State consistency issues
        uint256 unknownErrors; // Unexpected failures
    }
}
