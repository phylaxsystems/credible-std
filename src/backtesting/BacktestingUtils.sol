// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {BacktestingTypes} from "./BacktestingTypes.sol";

/// @title Backtesting Utilities
/// @notice Minimal utility functions for backtesting
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

        bytes memory result = new bytes(dataEnd - dataStart);
        for (uint256 k = 0; k < result.length; k++) {
            result[k] = outputBytes[dataStart + k];
        }
        return string(result);
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
        require(parts.length >= 9, "Invalid transaction data format");

        uint256 count = stringToUint(parts[0]);
        require(count > 0, "No transactions found");

        transactions = new BacktestingTypes.TransactionData[](count);

        // Each transaction has 8 fields: hash|from|to|value|data|block|txIndex|gasPrice
        uint256 fieldsPerTransaction = 8;
        uint256 expectedParts = 1 + (count * fieldsPerTransaction); // +1 for count at beginning
        require(parts.length >= expectedParts, "Insufficient transaction data");

        for (uint256 i = 0; i < count; i++) {
            uint256 startIndex = 1 + (i * fieldsPerTransaction); // Skip count at beginning

            transactions[i] = BacktestingTypes.TransactionData({
                hash: stringToBytes32(parts[startIndex]),
                from: stringToAddress(parts[startIndex + 1]),
                to: stringToAddress(parts[startIndex + 2]),
                value: stringToUint(parts[startIndex + 3]),
                data: hexStringToBytes(parts[startIndex + 4]),
                blockNumber: stringToUint(parts[startIndex + 5]),
                transactionIndex: stringToUint(parts[startIndex + 6]),
                gasPrice: stringToUint(parts[startIndex + 7])
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
}
