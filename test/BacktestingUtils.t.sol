// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BacktestingUtils} from "../src/utils/BacktestingUtils.sol";
import {BacktestingTypes} from "../src/utils/BacktestingTypes.sol";

/// @title BacktestingUtils Unit Tests
/// @notice Tests parsing and utility functions without RPC access
contract BacktestingUtilsTest is Test {
    /// @notice Test hex string to uint256 conversion
    function testStringToUint_Hex() public pure {
        assertEq(BacktestingUtils.stringToUint("0x0"), 0);
        assertEq(BacktestingUtils.stringToUint("0x1"), 1);
        assertEq(BacktestingUtils.stringToUint("0xa"), 10);
        assertEq(BacktestingUtils.stringToUint("0xff"), 255);
        assertEq(BacktestingUtils.stringToUint("0x100"), 256);
        assertEq(BacktestingUtils.stringToUint("0xDEADBEEF"), 3735928559);
    }

    /// @notice Test decimal string to uint256 conversion
    function testStringToUint_Decimal() public pure {
        assertEq(BacktestingUtils.stringToUint("0"), 0);
        assertEq(BacktestingUtils.stringToUint("1"), 1);
        assertEq(BacktestingUtils.stringToUint("123"), 123);
        assertEq(BacktestingUtils.stringToUint("1000000"), 1000000);
    }

    /// @notice Test address parsing
    function testStringToAddress() public pure {
        assertEq(
            BacktestingUtils.stringToAddress("0x5fd84259d66Cd46123540766Be93DFE6D43130D7"),
            0x5fd84259d66Cd46123540766Be93DFE6D43130D7
        );
        assertEq(BacktestingUtils.stringToAddress("0x0000000000000000000000000000000000000000"), address(0));
    }

    /// @notice Test empty string returns address(0)
    function testStringToAddress_Empty() public pure {
        assertEq(BacktestingUtils.stringToAddress(""), address(0));
    }

    /// @notice Test bytes32 parsing
    function testStringToBytes32() public pure {
        bytes32 expected = 0xe5ebeb502ae9ac441fc2912513a7deb9e82bc4d89da91ca41b5fdd51bb96a288;
        bytes32 result =
            BacktestingUtils.stringToBytes32("0xe5ebeb502ae9ac441fc2912513a7deb9e82bc4d89da91ca41b5fdd51bb96a288");
        assertEq(result, expected);
    }

    /// @notice Test hex string to bytes conversion
    function testHexStringToBytes() public pure {
        bytes memory result = BacktestingUtils.hexStringToBytes("0x1234");
        assertEq(result.length, 2);
        assertEq(uint8(result[0]), 0x12);
        assertEq(uint8(result[1]), 0x34);
    }

    /// @notice Test hex string to bytes without 0x prefix
    function testHexStringToBytes_NoPrefix() public pure {
        bytes memory result = BacktestingUtils.hexStringToBytes("abcd");
        assertEq(result.length, 2);
        assertEq(uint8(result[0]), 0xab);
        assertEq(uint8(result[1]), 0xcd);
    }

    /// @notice Test bytes32 to hex string conversion
    function testBytes32ToHex() public pure {
        bytes32 input = 0xe5ebeb502ae9ac441fc2912513a7deb9e82bc4d89da91ca41b5fdd51bb96a288;
        string memory result = BacktestingUtils.bytes32ToHex(input);
        assertEq(result, "0xe5ebeb502ae9ac441fc2912513a7deb9e82bc4d89da91ca41b5fdd51bb96a288");
    }

    /// @notice Test function selector extraction
    function testExtractFunctionSelector() public pure {
        // transfer(address,uint256) selector = 0xa9059cbb
        bytes memory calldata_ = hex"a9059cbb000000000000000000000000abcdef";
        string memory selector = BacktestingUtils.extractFunctionSelector(calldata_);
        assertEq(selector, "0xa9059cbb");
    }

    /// @notice Test function selector extraction with short data
    function testExtractFunctionSelector_ShortData() public pure {
        bytes memory shortData = hex"ab";
        string memory selector = BacktestingUtils.extractFunctionSelector(shortData);
        assertEq(selector, "N/A");
    }

    /// @notice Test startsWith helper
    function testStartsWith() public pure {
        assertTrue(BacktestingUtils.startsWith("hello world", "hello"));
        assertTrue(BacktestingUtils.startsWith("hello", "hello"));
        assertFalse(BacktestingUtils.startsWith("hello", "world"));
        assertFalse(BacktestingUtils.startsWith("hi", "hello"));
    }

    /// @notice Test error type string conversion
    function testGetErrorTypeString() public pure {
        assertEq(BacktestingUtils.getErrorTypeString(BacktestingTypes.ValidationResult.Success), "PASS");
        assertEq(BacktestingUtils.getErrorTypeString(BacktestingTypes.ValidationResult.Skipped), "SKIP");
        assertEq(BacktestingUtils.getErrorTypeString(BacktestingTypes.ValidationResult.ReplayFailure), "REPLAY_FAIL");
        assertEq(
            BacktestingUtils.getErrorTypeString(BacktestingTypes.ValidationResult.AssertionFailed), "ASSERTION_FAIL"
        );
        assertEq(BacktestingUtils.getErrorTypeString(BacktestingTypes.ValidationResult.UnknownError), "UNKNOWN_ERROR");
    }

    /// @notice Test transaction data parsing from pipe-delimited string
    function testParseMultipleTransactions_Single() public pure {
        // Format: count|hash|from|to|value|data|blockNumber|txIndex|gasPrice|gasLimit|maxFeePerGas|maxPriorityFeePerGas
        string memory txData =
            "1|0xe5ebeb502ae9ac441fc2912513a7deb9e82bc4d89da91ca41b5fdd51bb96a288|0x6aef8553e34617e65a27bd51ef85c6980c178658|0xcba6a51a78b9b71c8c9db4f0d894e6734afe04f6|0x0|0xa9059cbb|28144849|5|0x3b9aca00|0x5208|0x0|0x0";

        BacktestingTypes.TransactionData[] memory txs = BacktestingUtils.parseMultipleTransactions(txData);

        assertEq(txs.length, 1);
        assertEq(txs[0].hash, 0xe5ebeb502ae9ac441fc2912513a7deb9e82bc4d89da91ca41b5fdd51bb96a288);
        assertEq(txs[0].from, 0x6AEf8553e34617e65A27bD51ef85c6980C178658);
        assertEq(txs[0].to, 0xCBa6A51A78B9b71C8C9dB4F0d894E6734AfE04f6);
        assertEq(txs[0].value, 0);
        assertEq(txs[0].blockNumber, 28144849);
        assertEq(txs[0].transactionIndex, 5);
        assertEq(txs[0].gasPrice, 1000000000); // 0x3b9aca00 = 1 gwei
    }

    /// @notice Test parsing zero transactions
    function testParseMultipleTransactions_Zero() public pure {
        string memory txData = "0";
        BacktestingTypes.TransactionData[] memory txs = BacktestingUtils.parseMultipleTransactions(txData);
        assertEq(txs.length, 0);
    }

    /// @notice Test decoding panic error
    function testDecodeRevertReason_Panic() public pure {
        // Panic(uint256) with code 0x01 (assertion failed)
        bytes memory panicData = abi.encodeWithSignature("Panic(uint256)", 0x01);
        string memory reason = BacktestingUtils.decodeRevertReason(panicData);
        assertEq(reason, "Panic: assertion failed");
    }

    /// @notice Test decoding Error(string)
    function testDecodeRevertReason_Error() public pure {
        bytes memory errorData = abi.encodeWithSignature("Error(string)", "test error");
        string memory reason = BacktestingUtils.decodeRevertReason(errorData);
        assertEq(reason, "test error");
    }

    /// @notice Test decoding unknown error
    function testDecodeRevertReason_Unknown() public pure {
        bytes memory shortData = hex"ab";
        string memory reason = BacktestingUtils.decodeRevertReason(shortData);
        assertEq(reason, "Unknown error");
    }

    /// @notice Test default script search paths are returned
    function testGetDefaultScriptSearchPaths() public pure {
        string[] memory paths = BacktestingUtils.getDefaultScriptSearchPaths();
        assertEq(paths.length, 6);
        assertEq(paths[0], "lib/credible-std/scripts/backtesting/transaction_fetcher.sh");
        assertEq(paths[1], "dependencies/credible-std/scripts/backtesting/transaction_fetcher.sh");
    }
}
