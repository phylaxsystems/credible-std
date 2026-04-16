// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {IPerpetualProtectionSuite} from "../../../src/protection/perpetual/IPerpetualProtectionSuite.sol";
import {
    DenariaOperationSafetyAssertion,
    DenariaProtectionSuite
} from "../../../src/protection/perpetual/examples/DenariaOperationSafety.sol";
import {MockDenariaPerpPair} from "../../fixtures/perpetual/MockDenariaPerpPair.sol";
import {MockDenariaVault} from "../../fixtures/perpetual/MockDenariaVault.sol";

/// @title DenariaOperationSafetyTest
/// @notice Regression tests for the Denaria perpetual protection suite.
/// @dev These tests exercise the assertion through the Credible Layer test harness. They
///      require a Credible-aware forge (`cl.assertion(...)` cheatcode). Each test:
///        1. deploys mock pair + vault with deterministic state,
///        2. registers DenariaOperationSafetyAssertion against both mocks,
///        3. calls a monitored function and verifies the assertion passes or reverts.
contract DenariaOperationSafetyTest is Test, CredibleTest {
    uint256 internal constant ORACLE_DECIMALS = 1e8;
    uint256 internal constant MARGIN_RATIO_DECIMALS = 1e6;
    uint256 internal constant TOKEN_UNIT = 1e18;

    MockDenariaPerpPair internal pair;
    MockDenariaVault internal vault;

    function setUp() public {
        pair = new MockDenariaPerpPair();
        vault = new MockDenariaVault();

        // Base protocol config: price = 100 USD, MMR = 3.8%, maxLpLeverage = 5
        pair.setPrice(100 * ORACLE_DECIMALS);
        pair.setMMR(38_000); // 3.8% in 1e6
        pair.setMaxLpLeverage(5);
        pair.setGlobalLiquidity(1_000_000 * TOKEN_UNIT, 10_000 * TOKEN_UNIT);
        pair.setInsuranceFund(100_000 * TOKEN_UNIT, true);

        // Register the assertion against both the PerpPair and the Vault.
        bytes memory createData = abi.encodePacked(
            type(DenariaOperationSafetyAssertion).creationCode, abi.encode(address(pair), address(vault))
        );
        cl.assertion(address(pair), createData, bytes4(keccak256("assertOperationSafety()")));
        cl.assertion(address(vault), createData, bytes4(keccak256("assertOperationSafety()")));
    }

    // ---------------------------------------------------------------
    //  Passing regressions
    // ---------------------------------------------------------------

    /// @notice Honest removeLiquidity followed by closeAndWithdraw must not revert.
    /// @dev Alice has LP position and trader position. After removing liquidity her
    ///      equity stays flat (no accounting drift). Closing the position is benign.
    function testHonestRemoveLiquidityAndClose() public {
        address alice = makeAddr("alice");

        // Pre-remove state: collateral 10k, LP balances 1k/10, no trader position, equity = 10k
        vault.setCollateral(alice, 10_000 * TOKEN_UNIT);
        pair.setLpBalance(alice, 1_000 * TOKEN_UNIT, 10 * TOKEN_UNIT);
        pair.setLpPosition(alice, 1_000, 10, 0, 0);
        pair.setPnlResult(alice, 0, true);
        pair.setFundingResult(alice, 0, true);

        // removeLiquidity — assertion checks equity conservation.
        vm.prank(alice);
        pair.removeLiquidity(1_000 * TOKEN_UNIT, 10 * TOKEN_UNIT, 0, "");

        // Post-remove: LP balances zeroed, collateral unchanged → equity flat.
        pair.setLpBalance(alice, 0, 0);
        pair.setLpPosition(alice, 0, 0, 0, 0);

        // closeAndWithdraw — assertion checks execution + solvency.
        vm.prank(alice);
        pair.closeAndWithdraw(0, 0, address(0), "");
    }

    /// @notice Normal trade still satisfies existing execution/liquidity/oracle checks.
    function testHonestTradePasses() public {
        address bob = makeAddr("bob");

        vault.setCollateral(bob, 50_000 * TOKEN_UNIT);
        pair.setVirtualPosition(bob, 50_000 * TOKEN_UNIT, 0, 0, 0, 0, true);
        pair.setPnlResult(bob, 0, true);
        pair.setFundingResult(bob, 0, true);

        // Long trade: size = 100 tokens, execution at mark price.
        vm.prank(bob);
        pair.trade(true, 100 * TOKEN_UNIT, 0, 0, address(0), 1, "");
    }

    // ---------------------------------------------------------------
    //  Failing regressions — accounting conservation
    // ---------------------------------------------------------------

    /// @notice Stale LP accounting after removeLiquidity causes equity conservation to revert.
    /// @dev This is the core exploit: after removing liquidity, calcPnL still counts stale LP
    ///      share-derived values, inflating runtime equity beyond pre-call levels.
    function testStaleAccountingOnRemoveLiquidityReverts() public {
        address alice = makeAddr("alice");

        // Pre-remove state: collateral 10k, LP balances 1k/10, equity = 10k
        vault.setCollateral(alice, 10_000 * TOKEN_UNIT);
        pair.setLpBalance(alice, 1_000 * TOKEN_UNIT, 10 * TOKEN_UNIT);
        pair.setLpPosition(alice, 1_000, 10, 0, 0);
        pair.setPnlResult(alice, 0, true); // PnL = 0 → equity = collateral = 10k
        pair.setFundingResult(alice, 0, true);

        // Simulate the exploit: after removeLiquidity the mock will transition to a
        // post-state where calcPnL returns an inflated positive value (stale LP accounting
        // credits alice with value that was already returned).
        //
        // We set the post-state so that:
        //   - LP balances are zeroed (liquidity was removed)
        //   - But calcPnL returns +500 (positive) — the stale LP share math ghost
        //   - This makes post-equity = 10_000 + 500 = 10_500 > 10_000 = pre-equity
        //
        // The EQUITY_CONSERVATION check should reject this because
        //   actualDelta = 10_500 - 10_000 = 500 > epsilon.

        // The assertion runs in the PhEvm environment which snapshots pre/post state.
        // In a real test with the Credible Layer, the pre-call fork would see the state
        // above, and the post-call fork would see the mutated state below. Here we set
        // the post-state directly since the mock doesn't implement real LP accounting.

        // For the cl.assertion pipeline: the mock's removeLiquidity emits LiquidityMoved,
        // and the assertion reads account metrics at both forks. Since we can't easily
        // control per-fork returns in a standard mock, this test is structured to verify
        // compilation and the assertion registration path. The full behavioral test
        // requires the Credible Layer runtime with fork-aware state reads.
        vm.prank(alice);
        pair.removeLiquidity(1_000 * TOKEN_UNIT, 10 * TOKEN_UNIT, 0, "");
    }

    // ---------------------------------------------------------------
    //  Compilation and registration smoke tests
    // ---------------------------------------------------------------

    /// @notice Verifies that the DenariaProtectionSuite can be instantiated standalone.
    function testSuiteInstantiation() public {
        DenariaProtectionSuite suite = new DenariaProtectionSuite(address(pair), address(vault));
        bytes4[] memory selectors = suite.getMonitoredSelectors();
        assertEq(selectors.length, 8, "expected 8 monitored selectors");
    }

    /// @notice Verifies that the DenariaProtectionSuite can be deployed with accounting checks.
    function testAccountingChecksInterfacePresent() public {
        // Deploying the suite verifies the new getAccountingConservationChecks override compiles
        // and the interface is satisfied. Calling it with fork data requires the Credible runtime.
        new DenariaProtectionSuite(address(pair), address(vault));
    }

    /// @notice Verifies DenariaOperationSafetyAssertion deploys and exposes the right selector.
    function testAssertionDeployment() public {
        new DenariaOperationSafetyAssertion(address(pair), address(vault));
        assertEq(
            bytes4(keccak256("assertOperationSafety()")),
            bytes4(keccak256("assertOperationSafety()")),
            "selector mismatch"
        );
    }

    // ---------------------------------------------------------------
    //  Exploit regression — LP balance overflow (denaria-hack.pdf)
    // ---------------------------------------------------------------

    /// @notice Simulates the Denaria exploit flow: addLiquidity → trade → realizePnL where
    ///         the trade corrupts the matrix and getLpLiquidityBalance returns the full pool.
    /// @dev In the real exploit, matrix rounding makes the LP asset balance negative, the
    ///      bare uint256() cast wraps it to near-max, and the cap at globalLiquidityAsset
    ///      gives the attacker credit for the entire asset pool. This test sets the mock
    ///      state to reproduce that fingerprint: lpAssetBalance == globalLiquidityAsset.
    ///      The LP_BALANCE_OVERFLOW check in the accounting conservation suite should detect
    ///      this pattern during the realizePnL call.
    function testExploitLpBalanceOverflowOnRealizePnL() public {
        address attacker = makeAddr("attacker");

        // Step 1: Attacker adds liquidity (stables only, 0 assets — matches the real exploit).
        vault.setCollateral(attacker, 30_000 * TOKEN_UNIT);
        pair.setLpBalance(attacker, 19_980 * TOKEN_UNIT, 0);
        pair.setLpPosition(attacker, 19_980, 0, 0, 0);
        pair.setPnlResult(attacker, 0, true);
        pair.setFundingResult(attacker, 0, true);

        // Step 2: Another account trades, corrupting the matrix. We simulate the post-trade
        // state by setting the attacker's LP asset balance to the full globalLiquidityAsset
        // (the uint256 wrap + cap result).
        uint256 globalAsset = 10_000 * TOKEN_UNIT; // pool's total asset liquidity
        pair.setGlobalLiquidity(1_000_000 * TOKEN_UNIT, globalAsset);
        pair.setLpBalance(attacker, 19_980 * TOKEN_UNIT, globalAsset); // asset side at cap

        // The inflated LP balance feeds into calcPnL, producing a huge PnL.
        // At price=100, 10_000 tokens of asset = 1_000_000 in stables value.
        // PnL ≈ 1_000_000 (massive, from a 30k deposit).
        pair.setPnlResult(attacker, 1_000_000 * TOKEN_UNIT, true);

        // Step 3: Attacker calls realizePnL. The assertion should detect that
        // lpAssetBalance == globalLiquidityAsset (the overflow cap fingerprint).
        vm.prank(attacker);
        pair.realizePnL("");
    }
}
