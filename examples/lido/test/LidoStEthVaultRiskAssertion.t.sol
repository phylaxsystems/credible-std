// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {LidoStEthVaultRiskAssertion} from "../src/LidoStEthVaultRiskAssertion.sol";
import {MockERC20, MockAavePool, MockChainlinkFeed, MockRateSource, MockLidoVault} from "./LidoMocks.sol";

contract LidoStEthVaultRiskAssertionTest is Test, CredibleTest {
    MockLidoVault internal vault;
    MockAavePool internal pool;
    MockChainlinkFeed internal feed;
    MockRateSource internal rateSource;
    MockERC20 internal weth; // borrowed asset
    MockERC20 internal debtWeth; // borrowed-asset debt token
    MockERC20 internal collateral; // collateral asset (wstETH)
    MockERC20 internal aWstEth; // collateral supply token

    address internal borrowReserve = makeAddr("borrowReserve");
    address internal collReserve = makeAddr("collReserve");

    // Healthy baseline: HF 2.0, $210 collateral / $200 debt (1.05x), reserves fully cover exit.
    uint256 internal constant COLLATERAL = 210e8;
    uint256 internal constant DEBT = 200e8;
    uint256 internal constant SUPPLIED = 100 ether;
    uint256 internal constant VAULT_DEBT = 50 ether;

    function setUp() public {
        vault = new MockLidoVault();
        pool = new MockAavePool();
        feed = new MockChainlinkFeed(1e18, block.timestamp); // on peg, fresh
        rateSource = new MockRateSource(1e18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        debtWeth = new MockERC20("Variable Debt WETH", "vWETH", 18);
        collateral = new MockERC20("Wrapped stETH", "wstETH", 18);
        aWstEth = new MockERC20("Aave wstETH", "awstETH", 18);

        pool.setAccount(address(vault), COLLATERAL, DEBT, 2e18);
        aWstEth.setBalance(address(vault), SUPPLIED);
        collateral.setBalance(collReserve, SUPPLIED); // fully withdrawable
        debtWeth.setBalance(address(vault), VAULT_DEBT);
        weth.setBalance(borrowReserve, VAULT_DEBT); // fully covers exit
    }

    function _baseConfig() internal view returns (LidoStEthVaultRiskAssertion.RiskConfig memory c) {
        c.vault = address(vault);
        c.aavePool = address(pool);
        c.stEthEthFeed = address(feed);
        c.stEthEthFeedDecimals = 18;
        c.maxDepegBps = 100; // 1%
        c.maxFeedStalenessSecs = 0;
        c.rateSource = address(rateSource);
        c.borrowedAsset = address(weth);
        c.borrowedAssetReserve = borrowReserve;
        c.borrowedAssetDebtToken = address(debtWeth);
        c.collateralAsset = address(collateral);
        c.collateralAssetReserve = collReserve;
        c.collateralAssetSupplyToken = address(aWstEth);
        c.minHealthFactor = 1.01e18;
        c.reduceOnlyHealthFactor = 1.05e18;
        c.minCollateralRatioBps = 10_500; // 1.05x
        c.minExitLiquidityBps = 10_000;
        c.minCollateralLiquidityBps = 10_000;
    }

    function _arm(bytes4 sel, LidoStEthVaultRiskAssertion.RiskConfig memory c) internal {
        bytes memory createData = abi.encodePacked(type(LidoStEthVaultRiskAssertion).creationCode, abi.encode(c));
        cl.assertion(address(vault), createData, sel);
    }

    function _arm(bytes4 sel) internal {
        _arm(sel, _baseConfig());
    }

    // --- assertRiskRegime: healthy paths -----------------------------------

    function retiredUniversalRiskPolicyHealthyDebtGrowthPasses() public {
        weth.setBalance(borrowReserve, 100 ether); // reserve covers the larger debt
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        // Grow debt to $210 / 60 WETH while staying healthy and fully covered.
        vault.borrowMore(pool, 230e8, 210e8, 1.9e18, debtWeth, 60 ether);
    }

    function retiredUniversalRiskPolicyReduceOnlyAllowsDeleverage() public {
        pool.setAccount(address(vault), COLLATERAL, DEBT, 1.04e18); // unhealthy: below comfort band
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        // Repaying debt and improving HF is always allowed, even in reduce-only.
        vault.setPosition(pool, COLLATERAL, 150e8, 1.06e18);
    }

    // --- assertRiskRegime: reduce-only triggers ----------------------------

    function retiredUniversalRiskPolicyUnhealthyDebtGrowthTrips() public {
        pool.setAccount(address(vault), COLLATERAL, DEBT, 1.04e18); // below comfort band
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        vm.expectRevert(bytes("LidoVault: reduce-only regime, debt increased"));
        vault.borrowMore(pool, COLLATERAL, 210e8, 1.04e18, debtWeth, 60 ether);
    }

    function retiredUniversalRiskPolicyUnhealthyHealthFactorDeclineTrips() public {
        pool.setAccount(address(vault), COLLATERAL, DEBT, 1.04e18); // below comfort band
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        // Debt unchanged but HF slips further: not allowed while reduce-only.
        vm.expectRevert(bytes("LidoVault: reduce-only regime, health factor declined"));
        vault.setPosition(pool, COLLATERAL, DEBT, 1.02e18);
    }

    function retiredUniversalRiskPolicyDepegBlocksCollateralGrowth() public {
        feed.setAnswer(0.95e18); // 5% off peg, well past the 1% band
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        vm.expectRevert(bytes("LidoVault: reduce-only regime, collateral exposure increased"));
        vault.setSupplied(aWstEth, 150 ether);
    }

    function retiredUniversalRiskPolicyUnreadableRateBlocksDebtGrowth() public {
        rateSource.setReverts(true); // share pricing not trustworthy
        weth.setBalance(borrowReserve, 100 ether);
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        vm.expectRevert(bytes("LidoVault: reduce-only regime, debt increased"));
        vault.borrowMore(pool, 230e8, 210e8, 1.9e18, debtWeth, 60 ether);
    }

    function retiredUniversalRiskPolicyIlliquidCollateralBlocksCollateralGrowth() public {
        collateral.setBalance(collReserve, 50 ether); // reserve holds < 100% of supplied
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        vm.expectRevert(bytes("LidoVault: reduce-only regime, collateral exposure increased"));
        vault.setSupplied(aWstEth, 150 ether);
    }

    // --- assertRiskRegime: liquidity guards --------------------------------

    function retiredUniversalRiskPolicyInsufficientExitLiquidityTrips() public {
        // Healthy, but the borrowed reserve cannot cover the grown debt (50 < 100 WETH).
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        vm.expectRevert(bytes("LidoVault: insufficient exit liquidity for new debt"));
        vault.borrowMore(pool, 230e8, 210e8, 1.9e18, debtWeth, 100 ether);
    }

    function retiredUniversalRiskPolicyCollateralNotWithdrawableTrips() public {
        // Healthy and liquid pre-state, but deepening the supply leaves it under-covered.
        _arm(LidoStEthVaultRiskAssertion.assertRiskRegime.selector);

        vm.expectRevert(bytes("LidoVault: collateral not withdrawable on demand"));
        vault.setSupplied(aWstEth, 150 ether); // reserve still only 100
    }

    // --- assertPositionEnvelope --------------------------------------------

    function retiredUniversalRiskPolicyEnvelopePasses() public {
        _arm(LidoStEthVaultRiskAssertion.assertPositionEnvelope.selector);

        vault.borrowMore(pool, 230e8, 210e8, 1.9e18, debtWeth, 60 ether);
    }

    function retiredUniversalRiskPolicyEnvelopeIgnoresDebtFreePosition() public {
        _arm(LidoStEthVaultRiskAssertion.assertPositionEnvelope.selector);

        // No debt: the envelope has nothing to enforce.
        vault.setPosition(pool, 50e8, 0, 0);
    }

    function retiredUniversalRiskPolicyHealthFactorBelowFloorTrips() public {
        _arm(LidoStEthVaultRiskAssertion.assertPositionEnvelope.selector);

        vm.expectRevert(bytes("LidoVault: health factor below floor"));
        vault.setPosition(pool, COLLATERAL, DEBT, 1.005e18); // below the 1.01 floor
    }

    function retiredUniversalRiskPolicyHealthFactorDeclineBelowBandTrips() public {
        _arm(LidoStEthVaultRiskAssertion.assertPositionEnvelope.selector);

        // Above the floor but slipping below the comfort band while declining.
        vm.expectRevert(bytes("LidoVault: health factor declined below comfort band"));
        vault.setPosition(pool, COLLATERAL, DEBT, 1.03e18);
    }

    function retiredUniversalRiskPolicyCollateralRatioBelowMinTrips() public {
        _arm(LidoStEthVaultRiskAssertion.assertPositionEnvelope.selector);

        // HF holds, but $205 collateral / $200 debt is 1.025x, below the 1.05x minimum.
        vm.expectRevert(bytes("LidoVault: collateral ratio below minimum"));
        vault.setPosition(pool, 205e8, DEBT, 1.5e18);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroVault() public {
        LidoStEthVaultRiskAssertion.RiskConfig memory c = _baseConfig();
        c.vault = address(0);
        vm.expectRevert(bytes("LidoVault: zero vault"));
        new LidoStEthVaultRiskAssertion(c);
    }

    function testRejectsZeroPool() public {
        LidoStEthVaultRiskAssertion.RiskConfig memory c = _baseConfig();
        c.aavePool = address(0);
        vm.expectRevert(bytes("LidoVault: zero pool"));
        new LidoStEthVaultRiskAssertion(c);
    }

    function testRejectsFloorBelowLiquidation() public {
        LidoStEthVaultRiskAssertion.RiskConfig memory c = _baseConfig();
        c.minHealthFactor = 0.99e18;
        vm.expectRevert(bytes("LidoVault: floor below liquidation"));
        new LidoStEthVaultRiskAssertion(c);
    }

    function testRejectsBandBelowFloor() public {
        LidoStEthVaultRiskAssertion.RiskConfig memory c = _baseConfig();
        c.reduceOnlyHealthFactor = 1.0e18; // below minHealthFactor
        vm.expectRevert(bytes("LidoVault: band below floor"));
        new LidoStEthVaultRiskAssertion(c);
    }

    function testRejectsZeroBorrowedAssetWhenExitLiquiditySet() public {
        LidoStEthVaultRiskAssertion.RiskConfig memory c = _baseConfig();
        c.borrowedAsset = address(0);
        vm.expectRevert(bytes("LidoVault: zero borrowed asset"));
        new LidoStEthVaultRiskAssertion(c);
    }

    function testRejectsZeroCollateralAssetWhenCollLiquiditySet() public {
        LidoStEthVaultRiskAssertion.RiskConfig memory c = _baseConfig();
        c.collateralAsset = address(0);
        vm.expectRevert(bytes("LidoVault: zero collateral asset"));
        new LidoStEthVaultRiskAssertion(c);
    }

    function testDeploys() public {
        LidoStEthVaultRiskAssertion assertion = new LidoStEthVaultRiskAssertion(_baseConfig());
        assertTrue(address(assertion) != address(0));
    }
}
