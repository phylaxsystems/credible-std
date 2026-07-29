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
    // USDC on Optimism Sepolia
    address constant USDC_OP_SEPOLIA = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;

    /// @notice A `transfer(address,uint256)` of 10 USDC in block 31336940, the one transaction the
    ///         block-range suite above discovers over its window, pinned here by hash.
    bytes32 constant TRANSFER_TX = 0xbdfa042cfaa2c5305dc131e4fb1ef50bf43b2654ab511a2913444ea614f5eba7;

    /// @notice Backtest one transaction by hash and check the ERC20 invariant holds on it.
    function testSingleTransactionBacktest() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktestForTransaction(
            TRANSFER_TX,
            USDC_OP_SEPOLIA,
            type(ERC20Assertion).creationCode,
            ERC20Assertion.assertionTransferInvariant.selector,
            _rpcUrl()
        );

        _assertExactlyOneSuccessfulValidation(results);
    }

    /// @notice Assert the backtest actually validated the transaction.
    /// @dev `assertionFailures == 0` alone is satisfied by a transaction that was skipped, failed to
    ///      replay, or errored, so the assertion may never have run and the test still passes. The
    ///      counters are tracked independently, so all of them have to be pinned for the result to
    ///      mean "one transaction was replayed and the invariant held on it".
    function _assertExactlyOneSuccessfulValidation(BacktestingTypes.BacktestingResults memory results) internal pure {
        assertEq(results.totalTransactions, 1, "the pinned transaction is the only one backtested");
        assertEq(results.successfulValidations, 1, "the assertion did not run successfully");
        assertEq(results.assertionFailures, 0, "a plain transfer keeps the invariant");
        assertEq(results.skippedTransactions, 0, "the transaction was skipped rather than validated");
        assertEq(results.replayFailures, 0, "the transaction failed to replay");
        assertEq(results.unknownErrors, 0, "the backtest hit an unknown error");
    }

    /// @dev `OP_SEPOLIA_RPC_URL` overrides the public endpoint the block-range suite also uses.
    function _rpcUrl() internal view returns (string memory) {
        try vm.envString("OP_SEPOLIA_RPC_URL") returns (string memory url) {
            if (bytes(url).length > 0) {
                return url;
            }
        } catch {}
        return "https://sepolia.optimism.io";
    }
}
