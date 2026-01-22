// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {BacktestingTypes} from "./BacktestingTypes.sol";

/// @title BacktestingUtils
/// @author Phylax Systems
/// @notice Utility functions for the backtesting framework
/// @dev Provides parsing, string manipulation, and error decoding utilities
/// used internally by CredibleTestWithBacktesting
library BacktestingUtils {
    using Strings for uint256;

    /// @notice Extract transaction data from fetcher output
    function extractDataLine(string memory output) internal pure returns (string memory) {
        bytes memory outputBytes = bytes(output);
        bytes memory marker = bytes("TRANSACTION_DATA:");
        uint256[] memory positions = new uint256[](10); // Max 10 markers
        uint256 markerCount = 0;

        // Find all occurrences of the marker
        for (uint256 i = 0; i <= outputBytes.length - marker.length && markerCount < 10; i++) {
            bool matches = true;
            for (uint256 j = 0; j < marker.length; j++) {
                if (outputBytes[i + j] != marker[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                positions[markerCount] = i;
                markerCount++;
            }
        }

        // We need at least 3 markers: START, DATA, END
        if (markerCount < 3) {
            return "";
        }

        // Extract data from the second marker (index 1)
        uint256 dataStart = positions[1] + marker.length;
        uint256 dataEnd = positions[2];

        // Trim trailing whitespace/newlines
        while (dataEnd > dataStart && _isWhitespace(outputBytes[dataEnd - 1])) {
            dataEnd--;
        }

        bytes memory result = new bytes(dataEnd - dataStart);
        for (uint256 k = 0; k < result.length; k++) {
            result[k] = outputBytes[dataStart + k];
        }
        return string(result);
    }

    /// @notice Check if a character is whitespace
    function _isWhitespace(bytes1 char) private pure returns (bool) {
        return char == 0x20 || char == 0x09 || char == 0x0a || char == 0x0d; // space, tab, newline, carriage return
    }

    /// @notice Simple pipe-delimited string splitter
    function splitString(string memory str, string memory) internal pure returns (string[] memory) {
        bytes memory strBytes = bytes(str);

        // Count pipes
        uint256 count = 1;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == "|") count++;
        }

        string[] memory parts = new string[](count);
        uint256 partIndex = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == "|") {
                bytes memory part = new bytes(i - start);
                for (uint256 j = 0; j < part.length; j++) {
                    part[j] = strBytes[start + j];
                }
                parts[partIndex++] = string(part);
                start = i + 1;
            }
        }
        return parts;
    }

    /// @notice Parse hex or decimal string to uint256
    function stringToUint(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        if (b.length >= 2 && b[0] == "0" && b[1] == "x") {
            uint256 result = 0;
            for (uint256 i = 2; i < b.length; i++) {
                result = result * 16 + _hexCharToUint8(b[i]);
            }
            return result;
        }
        return Strings.parseUint(str);
    }

    /// @notice Parse hex address string to address
    function stringToAddress(string memory str) internal pure returns (address) {
        // Handle empty string (contract creation) as address(0)
        if (bytes(str).length == 0) {
            return address(0);
        }
        return Strings.parseAddress(str);
    }

    /// @notice Parse hex string to bytes32
    function stringToBytes32(string memory str) internal pure returns (bytes32) {
        bytes memory b = bytes(str);
        require(b.length == 66 && b[0] == "0" && b[1] == "x", "Invalid bytes32 hex");

        uint256 result = 0;
        for (uint256 i = 2; i < 66; i++) {
            result = result * 16 + _hexCharToUint8(b[i]);
        }
        return bytes32(result);
    }

    /// @notice Parse hex string to bytes
    function hexStringToBytes(string memory str) internal pure returns (bytes memory) {
        bytes memory b = bytes(str);
        uint256 start = (b.length >= 2 && b[0] == "0" && b[1] == "x") ? 2 : 0;
        bytes memory result = new bytes((b.length - start) / 2);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = bytes1(_hexCharToUint8(b[start + i * 2]) * 16 + _hexCharToUint8(b[start + i * 2 + 1]));
        }
        return result;
    }

    /// @notice Convert bytes32 to hex string
    function bytes32ToHex(bytes32 data) internal pure returns (string memory) {
        return Strings.toHexString(uint256(data), 32);
    }

    /// @notice Extract function selector from calldata
    function extractFunctionSelector(bytes memory data) internal pure returns (string memory) {
        return data.length >= 4 ? Strings.toHexString(uint32(bytes4(data)), 4) : "N/A";
    }

    /// @notice Parse multiple transactions from a single data line
    function parseMultipleTransactions(string memory txDataString)
        internal
        pure
        returns (BacktestingTypes.TransactionData[] memory transactions)
    {
        string[] memory parts = splitString(txDataString, "|");
        require(parts.length >= 1, "Invalid transaction data format");

        uint256 count = stringToUint(parts[0]);

        // Return empty array if no transactions
        if (count == 0) {
            return new BacktestingTypes.TransactionData[](0);
        }

        transactions = new BacktestingTypes.TransactionData[](count);

        // Each transaction has 8 fields (legacy) or 11 fields (extended):
        // hash|from|to|value|data|block|txIndex|gasPrice[|gasLimit|maxFeePerGas|maxPriorityFeePerGas]
        uint256 legacyFieldsPerTransaction = 8;
        uint256 extendedFieldsPerTransaction = 11;
        uint256 legacyExpectedParts = 1 + (count * legacyFieldsPerTransaction); // +1 for count at beginning
        uint256 extendedExpectedParts = 1 + (count * extendedFieldsPerTransaction);
        uint256 fieldsPerTransaction =
            parts.length >= extendedExpectedParts ? extendedFieldsPerTransaction : legacyFieldsPerTransaction;

        require(parts.length >= legacyExpectedParts, "Insufficient transaction data");

        for (uint256 i = 0; i < count; i++) {
            uint256 startIndex = 1 + (i * fieldsPerTransaction); // Skip count at beginning

            uint256 gasPrice = stringToUint(parts[startIndex + 7]);
            uint256 gasLimit = 0;
            uint256 maxFeePerGas = 0;
            uint256 maxPriorityFeePerGas = 0;

            if (fieldsPerTransaction == extendedFieldsPerTransaction) {
                gasLimit = stringToUint(parts[startIndex + 8]);
                maxFeePerGas = stringToUint(parts[startIndex + 9]);
                maxPriorityFeePerGas = stringToUint(parts[startIndex + 10]);
            }

            transactions[i] = BacktestingTypes.TransactionData({
                hash: stringToBytes32(parts[startIndex]),
                from: stringToAddress(parts[startIndex + 1]),
                to: stringToAddress(parts[startIndex + 2]),
                value: stringToUint(parts[startIndex + 3]),
                data: hexStringToBytes(parts[startIndex + 4]),
                blockNumber: stringToUint(parts[startIndex + 5]),
                transactionIndex: stringToUint(parts[startIndex + 6]),
                gasPrice: gasPrice,
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxPriorityFeePerGas
            });
        }
    }

    /// @notice Convert hex character to uint8
    function _hexCharToUint8(bytes1 char) private pure returns (uint8) {
        if (char >= "0" && char <= "9") return uint8(char) - 48;
        if (char >= "a" && char <= "f") return uint8(char) - 87;
        if (char >= "A" && char <= "F") return uint8(char) - 55;
        revert("Invalid hex char");
    }

    /// @notice Helper to get substring for debugging
    function substring(string memory str, uint256 start, uint256 len) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (start >= strBytes.length) return "";
        uint256 end = start + len;
        if (end > strBytes.length) end = strBytes.length;
        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = strBytes[start + i];
        }
        return string(result);
    }

    /// @notice Decode revert reason from error data
    /// @param data The error data from a failed call
    /// @return The decoded revert reason string
    function decodeRevertReason(bytes memory data) internal pure returns (string memory) {
        if (data.length < 4) return "Unknown error";

        // Extract selector
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }

        // Handle Panic(uint256) - selector 0x4e487b71
        if (selector == 0x4e487b71 && data.length >= 36) {
            uint256 panicCode;
            assembly {
                panicCode := mload(add(data, 36))
            }
            return _panicCodeToString(panicCode);
        }

        // Handle Error(string) - selector 0x08c379a0
        if (selector == 0x08c379a0 && data.length >= 68) {
            assembly {
                data := add(data, 4)
                mstore(data, sub(mload(data), 4))
            }
            return abi.decode(data, (string));
        }

        // Unknown error format - return hex of first 4 bytes
        return string.concat("Custom error: ", Strings.toHexString(uint32(selector), 4));
    }

    /// @notice Convert panic code to human-readable string
    function _panicCodeToString(uint256 code) private pure returns (string memory) {
        if (code == 0x00) return "Panic: generic/compiler panic";
        if (code == 0x01) return "Panic: assertion failed";
        if (code == 0x11) return "Panic: arithmetic overflow/underflow";
        if (code == 0x12) return "Panic: division by zero";
        if (code == 0x21) return "Panic: invalid enum value";
        if (code == 0x22) return "Panic: storage out of bounds";
        if (code == 0x31) return "Panic: pop from empty array";
        if (code == 0x32) return "Panic: array out-of-bounds access";
        if (code == 0x41) return "Panic: too much memory allocated";
        if (code == 0x51) return "Panic: uninitialized function pointer";
        return string.concat("Panic: unknown code 0x", Strings.toHexString(code));
    }

    /// @notice Convert bytes to hex string
    /// @param data The bytes to convert
    /// @return The hex string representation
    function bytesToHex(bytes memory data) internal pure returns (bytes memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            result[i * 2] = hexChars[uint8(data[i]) >> 4];
            result[i * 2 + 1] = hexChars[uint8(data[i]) & 0x0f];
        }
        return result;
    }

    /// @notice Get human-readable error type string from validation result
    /// @param result The validation result enum
    /// @return The human-readable string representation
    function getErrorTypeString(BacktestingTypes.ValidationResult result) internal pure returns (string memory) {
        if (result == BacktestingTypes.ValidationResult.Success) return "PASS";
        if (result == BacktestingTypes.ValidationResult.Skipped) return "SKIP";
        if (result == BacktestingTypes.ValidationResult.ReplayFailure) return "REPLAY_FAIL";
        if (result == BacktestingTypes.ValidationResult.AssertionFailed) return "ASSERTION_FAIL";
        return "UNKNOWN_ERROR";
    }

    /// @notice Check if a string starts with a prefix
    /// @param str The string to check
    /// @param prefix The prefix to look for
    /// @return True if str starts with prefix
    function startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (prefixBytes.length > strBytes.length) return false;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    /// @notice Get the standard search paths for transaction_fetcher.sh
    /// @return Array of paths to check, in order of preference
    function getDefaultScriptSearchPaths() internal pure returns (string[] memory) {
        string[] memory paths = new string[](3);
        paths[0] = "lib/credible-std/scripts/backtesting/transaction_fetcher.sh";
        paths[1] = "dependencies/credible-std/scripts/backtesting/transaction_fetcher.sh";
        paths[2] = "../credible-std/scripts/backtesting/transaction_fetcher.sh";
        return paths;
    }
}
