// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {MellowRiskManagerBalanceAssertion} from "../src/MellowRiskManagerBalanceAssertion.sol";
import {MockMellowRiskManager} from "./MellowMocks.sol";

contract MellowRiskManagerBalanceAssertionTest is Test, CredibleTest {
    MockMellowRiskManager internal riskManager;
    address internal asset = makeAddr("asset");
    address internal subvault = makeAddr("subvault");

    function setUp() public {
        riskManager = new MockMellowRiskManager();
        riskManager.setVaultBalance(1_000e18); // approximate shares held by the vault
        riskManager.setSubvaultBalance(subvault, 200e18);
    }

    function _arm(bytes4 sel, uint256 maxModifyBps, uint256 absoluteFloorShares) internal {
        bytes memory createData = abi.encodePacked(
            type(MellowRiskManagerBalanceAssertion).creationCode,
            abi.encode(address(riskManager), maxModifyBps, absoluteFloorShares)
        );
        cl.assertion(address(riskManager), createData, sel);
    }

    // --- Vault balance corrections -----------------------------------------

    function testVaultModifyWithinBoundPasses() public {
        // +10% of a 1000-share balance, under a 20% envelope.
        _arm(MellowRiskManagerBalanceAssertion.assertVaultBalanceModifyBounded.selector, 2_000, 0);
        riskManager.modifyVaultBalance(asset, 100e18);
    }

    function testVaultModifyExceedsBoundTrips() public {
        // -50% drain. The protocol does NOT bound negative corrections; the assertion does.
        _arm(MellowRiskManagerBalanceAssertion.assertVaultBalanceModifyBounded.selector, 2_000, 0);
        vm.expectRevert(bytes("MellowRisk: vault balance correction exceeds bound"));
        riskManager.modifyVaultBalance(asset, -500e18);
    }

    // --- Subvault balance corrections --------------------------------------

    function testSubvaultModifyWithinBoundPasses() public {
        // +10% of a 200-share subvault balance, under a 20% envelope.
        _arm(MellowRiskManagerBalanceAssertion.assertSubvaultBalanceModifyBounded.selector, 2_000, 0);
        riskManager.modifySubvaultBalance(subvault, asset, 20e18);
    }

    function testSubvaultModifyExceedsBoundTrips() public {
        // -75% rewrite of the subvault accounting.
        _arm(MellowRiskManagerBalanceAssertion.assertSubvaultBalanceModifyBounded.selector, 2_000, 0);
        vm.expectRevert(bytes("MellowRisk: subvault balance correction exceeds bound"));
        riskManager.modifySubvaultBalance(subvault, asset, -150e18);
    }

    // --- Absolute floor on a near-zero base --------------------------------

    function testAbsoluteFloorAllowsSmallBaseCorrection() public {
        // Pre-balance 0 → relative bound is 0; the absolute floor permits a genuine correction.
        riskManager.setVaultBalance(0);
        _arm(MellowRiskManagerBalanceAssertion.assertVaultBalanceModifyBounded.selector, 2_000, 50e18);
        riskManager.modifyVaultBalance(asset, 40e18);
    }

    function testAbsoluteFloorStillBounded() public {
        // Pre-balance 0, but a correction beyond the floor still trips.
        riskManager.setVaultBalance(0);
        _arm(MellowRiskManagerBalanceAssertion.assertVaultBalanceModifyBounded.selector, 2_000, 50e18);
        vm.expectRevert(bytes("MellowRisk: vault balance correction exceeds bound"));
        riskManager.modifyVaultBalance(asset, 60e18);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroRiskManager() public {
        vm.expectRevert(bytes("MellowRisk: zero risk manager"));
        new MellowRiskManagerBalanceAssertion(address(0), 2_000, 0);
    }

    function testRejectsZeroModifyBps() public {
        vm.expectRevert(bytes("MellowRisk: zero modify bps"));
        new MellowRiskManagerBalanceAssertion(address(riskManager), 0, 0);
    }

    function testDeploys() public {
        MellowRiskManagerBalanceAssertion assertion =
            new MellowRiskManagerBalanceAssertion(address(riskManager), 2_000, 0);
        assertTrue(address(assertion) != address(0));
    }
}
