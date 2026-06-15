// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {LidoStEthVaultNavAssertion} from "../src/LidoStEthVaultNavAssertion.sol";
import {MockERC20, MockWstETH, MockRateSource, MockAavePool, MockAaveOracle} from "./LidoMocks.sol";

contract LidoStEthVaultNavAssertionTest is Test, CredibleTest {
    MockRateSource internal rateSource; // the rate reporter (also the adopter)
    MockERC20 internal shareToken;
    MockERC20 internal weth; // base asset
    MockERC20 internal stEth;
    MockWstETH internal wstEth;
    MockAavePool internal pool;
    MockAaveOracle internal oracle;

    address internal vault = makeAddr("vault");
    address internal alice = makeAddr("alice");

    uint256 internal constant TOLERANCE_BPS = 50; // 0.5%

    function setUp() public {
        rateSource = new MockRateSource(1e18);
        shareToken = new MockERC20("Share", "SHARE", 18);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        stEth = new MockERC20("Lido stETH", "stETH", 18);
        wstEth = new MockWstETH();
        pool = new MockAavePool();
        oracle = new MockAaveOracle();

        // Idle 100 WETH backs 100 shares => NAV/share == 1.0.
        weth.setBalance(vault, 100 ether);
        shareToken.mint(alice, 100 ether);
    }

    function _arm(bytes4 sel, address aavePool, address aaveOracle) internal {
        bytes memory createData = abi.encodePacked(
            type(LidoStEthVaultNavAssertion).creationCode,
            abi.encode(
                vault,
                address(shareToken),
                address(rateSource),
                aavePool,
                aaveOracle,
                address(weth),
                address(stEth),
                address(wstEth),
                uint8(18),
                TOLERANCE_BPS
            )
        );
        cl.assertion(address(rateSource), createData, sel);
    }

    function _armIdleOnly(bytes4 sel) internal {
        _arm(sel, address(0), address(0));
    }

    // --- Rate-vs-NAV --------------------------------------------------------

    function testRateWithinTolerancePasses() public {
        _armIdleOnly(LidoStEthVaultNavAssertion.assertShareRateMatchesNav.selector);
        // NAV/share is 1.0; 1.004 sits inside the 0.5% band.
        rateSource.setRate(1.004e18);
    }

    function testRateAboveNavTrips() public {
        _armIdleOnly(LidoStEthVaultNavAssertion.assertShareRateMatchesNav.selector);
        vm.expectRevert(bytes("LidoVault: reported rate above on-chain NAV"));
        rateSource.setRate(1.1e18);
    }

    function testRateBelowNavTrips() public {
        _armIdleOnly(LidoStEthVaultNavAssertion.assertShareRateMatchesNav.selector);
        vm.expectRevert(bytes("LidoVault: reported rate below on-chain NAV"));
        rateSource.setRate(0.9e18);
    }

    function testCountsWstEthAtLidoRate() public {
        // Add 50 wstETH at 1.2 stEthPerToken = 60 stETH-eq; NAV 160 / 100 shares = 1.6.
        wstEth.setRate(1.2e18);
        wstEth.setBalance(vault, 50 ether);
        _armIdleOnly(LidoStEthVaultNavAssertion.assertShareRateMatchesNav.selector);

        rateSource.setRate(1.6e18);
    }

    function testZeroSupplyPasses() public {
        shareToken.burn(alice, 100 ether); // supply now 0
        _armIdleOnly(LidoStEthVaultNavAssertion.assertShareRateMatchesNav.selector);

        // No shares: nothing to price against, any reported rate is vacuously fine.
        rateSource.setRate(5e18);
    }

    function testInsolventBookTrips() public {
        oracle.setPrice(address(weth), 1e18); // base price: 1 base-currency unit == 1 WETH
        pool.setAccount(vault, 1e18, 1000e18, 1e18); // $1 collateral, $1000 debt
        _arm(LidoStEthVaultNavAssertion.assertShareRateMatchesNav.selector, address(pool), address(oracle));

        vm.expectRevert(bytes("LidoVault: vault book is insolvent"));
        rateSource.setRate(1e18);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("LidoVault: zero vault"));
        new LidoStEthVaultNavAssertion(
            address(0),
            address(shareToken),
            address(rateSource),
            address(0),
            address(0),
            address(weth),
            address(stEth),
            address(wstEth),
            18,
            TOLERANCE_BPS
        );
    }

    function testRejectsZeroRateSource() public {
        vm.expectRevert(bytes("LidoVault: zero rate source"));
        new LidoStEthVaultNavAssertion(
            vault,
            address(shareToken),
            address(0),
            address(0),
            address(0),
            address(weth),
            address(stEth),
            address(wstEth),
            18,
            TOLERANCE_BPS
        );
    }

    function testRejectsZeroOracleWhenPoolSet() public {
        vm.expectRevert(bytes("LidoVault: zero aave oracle"));
        new LidoStEthVaultNavAssertion(
            vault,
            address(shareToken),
            address(rateSource),
            address(pool),
            address(0),
            address(weth),
            address(stEth),
            address(wstEth),
            18,
            TOLERANCE_BPS
        );
    }

    function testRejectsToleranceTooLarge() public {
        vm.expectRevert(bytes("LidoVault: tolerance too large"));
        new LidoStEthVaultNavAssertion(
            vault,
            address(shareToken),
            address(rateSource),
            address(0),
            address(0),
            address(weth),
            address(stEth),
            address(wstEth),
            18,
            10_001
        );
    }

    function testDeploys() public {
        LidoStEthVaultNavAssertion assertion = new LidoStEthVaultNavAssertion(
            vault,
            address(shareToken),
            address(rateSource),
            address(pool),
            address(oracle),
            address(weth),
            address(stEth),
            address(wstEth),
            18,
            TOLERANCE_BPS
        );
        assertTrue(address(assertion) != address(0));
    }
}
