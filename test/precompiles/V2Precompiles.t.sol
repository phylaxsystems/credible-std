// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../src/CredibleTest.sol";
import {Target, TARGET} from "../../src/test-cases/common/Target.sol";

import {TestCallInputAt, TriggeringTx as CallInputAtTx} from "../../src/test-cases/precompiles/CallInputAt.sol";
import {TestContext, TriggeringTx as ContextTx} from "../../src/test-cases/precompiles/Context.sol";
import {TestMatchingCalls, TriggeringTx as MatchingCallsTx} from "../../src/test-cases/precompiles/MatchingCalls.sol";
import {TestGetLogsForCall, TriggeringTx as LogsForCallTx} from "../../src/test-cases/precompiles/GetLogsForCall.sol";
import {TestAssertionStorage, TriggeringTx as StorageTx} from "../../src/test-cases/precompiles/AssertionStorage.sol";
import {TestMathPrecompiles, TriggeringTx as MathTx} from "../../src/test-cases/precompiles/MathPrecompiles.sol";
import {
    TestErc20Transfers,
    MockErc20,
    TOKEN_A,
    TOKEN_B,
    TriggeringTx as Erc20Tx
} from "../../src/test-cases/precompiles/Erc20Transfers.sol";
import {
    TestConserveBalance,
    BalanceToken,
    TOKEN as BAL_TOKEN,
    TriggeringTx as ConserveTx
} from "../../src/test-cases/precompiles/ConserveBalance.sol";
import {
    TestOracleSanity,
    MockOracle,
    ORACLE,
    TriggeringTx as OracleTx
} from "../../src/test-cases/precompiles/OracleSanity.sol";
import {
    TestAssetsMatchSharePrice,
    MockVault,
    VAULT,
    TriggeringTx as VaultTx
} from "../../src/test-cases/precompiles/AssetsMatchSharePrice.sol";
import {
    TestInflowOutflowContextOutsideTrigger,
    TriggeringTx as InflowOutflowTx
} from "../../src/test-cases/precompiles/InflowOutflowContext.sol";

/// @notice cl.assertion-armed harness for the V2 precompile fixtures.
/// @dev Each test arms a single assertion function against its adopter, then deploys the
///      fixture's TriggeringTx so its constructor performs the watched operations.
contract V2PrecompilesTest is Test, CredibleTest {
    function _etchTarget() internal {
        vm.etch(address(TARGET), address(new Target()).code);
    }

    function _arm(address adopter, bytes memory createCode, bytes4 sel) internal {
        cl.assertion(adopter, createCode, sel);
    }

    // ── CallInputAt ─────────────────────────────────────────────────────────
    function test_CallInputAt_callInputAt() public {
        _etchTarget();
        _arm(address(TARGET), type(TestCallInputAt).creationCode, TestCallInputAt.callInputAt.selector);
        new CallInputAtTx();
    }

    function test_CallInputAt_emptyCalldataReturnsEmptyBytes() public {
        _etchTarget();
        _arm(
            address(TARGET), type(TestCallInputAt).creationCode, TestCallInputAt.emptyCalldataReturnsEmptyBytes.selector
        );
        new CallInputAtTx();
    }

    // ── Context ─────────────────────────────────────────────────────────────
    function test_Context_checkContext() public {
        _etchTarget();
        _arm(address(TARGET), type(TestContext).creationCode, TestContext.checkContext.selector);
        new ContextTx();
    }

    // ── MatchingCalls ───────────────────────────────────────────────────────
    function test_MatchingCalls_matchesAllWriteCalls() public {
        _etchTarget();
        _arm(address(TARGET), type(TestMatchingCalls).creationCode, TestMatchingCalls.matchesAllWriteCalls.selector);
        new MatchingCallsTx();
    }

    function test_MatchingCalls_staticCallTypeFilterMatchesOnlyStaticCalls() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMatchingCalls).creationCode,
            TestMatchingCalls.staticCallTypeFilterMatchesOnlyStaticCalls.selector
        );
        new MatchingCallsTx();
    }

    function test_MatchingCalls_callTypeFilterExcludesStaticCalls() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMatchingCalls).creationCode,
            TestMatchingCalls.callTypeFilterExcludesStaticCalls.selector
        );
        new MatchingCallsTx();
    }

    function test_MatchingCalls_topLevelOnlyExcludesNestedCalls() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMatchingCalls).creationCode,
            TestMatchingCalls.topLevelOnlyExcludesNestedCalls.selector
        );
        new MatchingCallsTx();
    }

    function test_MatchingCalls_successOnlyExcludesFailedCalls() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMatchingCalls).creationCode,
            TestMatchingCalls.successOnlyExcludesFailedCalls.selector
        );
        new MatchingCallsTx();
    }

    function test_MatchingCalls_limitTruncatesResultArray() public {
        _etchTarget();
        _arm(
            address(TARGET), type(TestMatchingCalls).creationCode, TestMatchingCalls.limitTruncatesResultArray.selector
        );
        new MatchingCallsTx();
    }

    // ── GetLogsForCall ──────────────────────────────────────────────────────
    function test_GetLogsForCall_logsAreScopedToTheirCall() public {
        _etchTarget();
        _arm(
            address(TARGET), type(TestGetLogsForCall).creationCode, TestGetLogsForCall.logsAreScopedToTheirCall.selector
        );
        new LogsForCallTx();
    }

    function test_GetLogsForCall_emptyQueryReturnsAllLogsInCallFrame() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestGetLogsForCall).creationCode,
            TestGetLogsForCall.emptyQueryReturnsAllLogsInCallFrame.selector
        );
        new LogsForCallTx();
    }

    function test_GetLogsForCall_nonMatchingSignatureReturnsEmpty() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestGetLogsForCall).creationCode,
            TestGetLogsForCall.nonMatchingSignatureReturnsEmpty.selector
        );
        new LogsForCallTx();
    }

    function test_GetLogsForCall_callWithoutLogsReturnsEmpty() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestGetLogsForCall).creationCode,
            TestGetLogsForCall.callWithoutLogsReturnsEmpty.selector
        );
        new LogsForCallTx();
    }

    // ── AssertionStorage ────────────────────────────────────────────────────
    function test_AssertionStorage_storeAndLoadRoundtrips() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestAssertionStorage).creationCode,
            TestAssertionStorage.storeAndLoadRoundtrips.selector
        );
        new StorageTx();
    }

    function test_AssertionStorage_existsReportsWrittenKeys() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestAssertionStorage).creationCode,
            TestAssertionStorage.existsReportsWrittenKeys.selector
        );
        new StorageTx();
    }

    function test_AssertionStorage_overwriteKeepsKeyExisting() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestAssertionStorage).creationCode,
            TestAssertionStorage.overwriteKeepsKeyExisting.selector
        );
        new StorageTx();
    }

    function test_AssertionStorage_valuesLeftDecreasesAsKeysAreWritten() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestAssertionStorage).creationCode,
            TestAssertionStorage.valuesLeftDecreasesAsKeysAreWritten.selector
        );
        new StorageTx();
    }

    // ── MathPrecompiles ─────────────────────────────────────────────────────
    function test_Math_mulDivDownRoundsTowardZero() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.mulDivDownRoundsTowardZero.selector
        );
        new MathTx();
    }

    function test_Math_mulDivUpRoundsAwayFromZero() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.mulDivUpRoundsAwayFromZero.selector
        );
        new MathTx();
    }

    function test_Math_mulDivHandlesWideIntermediates() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.mulDivHandlesWideIntermediates.selector
        );
        new MathTx();
    }

    function test_Math_normalizeDecimalsUpscalesAndDownscales() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.normalizeDecimalsUpscalesAndDownscales.selector
        );
        new MathTx();
    }

    function test_Math_ratioGePassesExactEquality() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.ratioGePassesExactEquality.selector
        );
        new MathTx();
    }

    function test_Math_ratioGeFailsWhenStrictlySmaller() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.ratioGeFailsWhenStrictlySmaller.selector
        );
        new MathTx();
    }

    function test_Math_ratioGeRespectsTolerance() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestMathPrecompiles).creationCode,
            TestMathPrecompiles.ratioGeRespectsTolerance.selector
        );
        new MathTx();
    }

    // ── Erc20Transfers ──────────────────────────────────────────────────────
    function _etchErc20() internal {
        bytes memory code = address(new MockErc20()).code;
        vm.etch(address(TOKEN_A), code);
        vm.etch(address(TOKEN_B), code);
    }

    function test_Erc20_getErc20TransfersReturnsAllTransfersForToken() public {
        _etchErc20();
        _arm(
            address(TOKEN_A),
            type(TestErc20Transfers).creationCode,
            TestErc20Transfers.getErc20TransfersReturnsAllTransfersForToken.selector
        );
        new Erc20Tx();
    }

    function test_Erc20_getErc20TransfersForTokensMergesAcrossTokens() public {
        _etchErc20();
        _arm(
            address(TOKEN_A),
            type(TestErc20Transfers).creationCode,
            TestErc20Transfers.getErc20TransfersForTokensMergesAcrossTokens.selector
        );
        new Erc20Tx();
    }

    function test_Erc20_changedErc20BalanceDeltasReturnsRawTransfers() public {
        _etchErc20();
        _arm(
            address(TOKEN_A),
            type(TestErc20Transfers).creationCode,
            TestErc20Transfers.changedErc20BalanceDeltasReturnsRawTransfers.selector
        );
        new Erc20Tx();
    }

    function test_Erc20_reduceErc20BalanceDeltasAggregatesByPair() public {
        _etchErc20();
        _arm(
            address(TOKEN_A),
            type(TestErc20Transfers).creationCode,
            TestErc20Transfers.reduceErc20BalanceDeltasAggregatesByPair.selector
        );
        new Erc20Tx();
    }

    function test_Erc20_unknownTokenReturnsEmpty() public {
        _etchErc20();
        _arm(
            address(TOKEN_A),
            type(TestErc20Transfers).creationCode,
            TestErc20Transfers.unknownTokenReturnsEmpty.selector
        );
        new Erc20Tx();
    }

    // ── ConserveBalance ─────────────────────────────────────────────────────
    function _etchBalanceToken() internal {
        vm.etch(address(BAL_TOKEN), address(new BalanceToken()).code);
    }

    function test_Conserve_conservedAccountReturnsTrue() public {
        _etchBalanceToken();
        _arm(
            address(BAL_TOKEN),
            type(TestConserveBalance).creationCode,
            TestConserveBalance.conservedAccountReturnsTrue.selector
        );
        new ConserveTx();
    }

    function test_Conserve_changedAccountReturnsFalse() public {
        _etchBalanceToken();
        _arm(
            address(BAL_TOKEN),
            type(TestConserveBalance).creationCode,
            TestConserveBalance.changedAccountReturnsFalse.selector
        );
        new ConserveTx();
    }

    function test_Conserve_identicalForksAlwaysConserve() public {
        _etchBalanceToken();
        _arm(
            address(BAL_TOKEN),
            type(TestConserveBalance).creationCode,
            TestConserveBalance.identicalForksAlwaysConserve.selector
        );
        new ConserveTx();
    }

    // ── OracleSanity ────────────────────────────────────────────────────────
    function _etchOracle() internal {
        vm.etch(address(ORACLE), address(new MockOracle()).code);
    }

    function test_Oracle_smallMoveWithinToleranceReturnsTrue() public {
        _etchOracle();
        _arm(
            address(ORACLE),
            type(TestOracleSanity).creationCode,
            TestOracleSanity.smallMoveWithinToleranceReturnsTrue.selector
        );
        new OracleTx();
    }

    function test_Oracle_largeMoveOutsideToleranceReturnsFalse() public {
        _etchOracle();
        _arm(
            address(ORACLE),
            type(TestOracleSanity).creationCode,
            TestOracleSanity.largeMoveOutsideToleranceReturnsFalse.selector
        );
        new OracleTx();
    }

    function test_Oracle_identicalForksAlwaysPass() public {
        _etchOracle();
        _arm(address(ORACLE), type(TestOracleSanity).creationCode, TestOracleSanity.identicalForksAlwaysPass.selector);
        new OracleTx();
    }

    // ── AssetsMatchSharePrice ───────────────────────────────────────────────
    function _etchVault() internal {
        vm.etch(address(VAULT), address(new MockVault()).code);
    }

    function test_Vault_proportionalDepositsKeepSharePriceConstant() public {
        _etchVault();
        _arm(
            address(VAULT),
            type(TestAssetsMatchSharePrice).creationCode,
            TestAssetsMatchSharePrice.proportionalDepositsKeepSharePriceConstant.selector
        );
        new VaultTx();
    }

    function test_Vault_tightTolerancePassesOnStableSharePrice() public {
        _etchVault();
        _arm(
            address(VAULT),
            type(TestAssetsMatchSharePrice).creationCode,
            TestAssetsMatchSharePrice.tightTolerancePassesOnStableSharePrice.selector
        );
        new VaultTx();
    }

    function test_Vault_identicalForksAlwaysPass() public {
        _etchVault();
        _arm(
            address(VAULT),
            type(TestAssetsMatchSharePrice).creationCode,
            TestAssetsMatchSharePrice.identicalForksAlwaysPass.selector
        );
        new VaultTx();
    }

    // ── InflowOutflowContext (outside-trigger zero-struct semantics) ────────
    function test_InflowOutflow_outflowContextOutsideTriggerIsZero() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestInflowOutflowContextOutsideTrigger).creationCode,
            TestInflowOutflowContextOutsideTrigger.outflowContextOutsideTriggerIsZero.selector
        );
        new InflowOutflowTx();
    }

    function test_InflowOutflow_inflowContextOutsideTriggerIsZero() public {
        _etchTarget();
        _arm(
            address(TARGET),
            type(TestInflowOutflowContextOutsideTrigger).creationCode,
            TestInflowOutflowContextOutsideTrigger.inflowContextOutsideTriggerIsZero.selector
        );
        new InflowOutflowTx();
    }
}
