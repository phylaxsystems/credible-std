// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {MellowConfigLockAssertion} from "../src/MellowConfigLockAssertion.sol";
import {MockMellowVault} from "./MellowMocks.sol";

contract MellowConfigLockAssertionTest is Test, CredibleTest {
    MockMellowVault internal vault;

    address internal oracleAddr = makeAddr("oracle");
    address internal shareManagerAddr = makeAddr("shareManager");
    address internal feeManagerAddr = makeAddr("feeManager");
    address internal riskManagerAddr = makeAddr("riskManager");
    address internal evil = makeAddr("evil");

    function setUp() public {
        vault = new MockMellowVault(oracleAddr, shareManagerAddr, feeManagerAddr, riskManagerAddr);
    }

    function _arm(bytes4 sel) internal {
        _arm(sel, oracleAddr, shareManagerAddr, feeManagerAddr, riskManagerAddr);
    }

    function _arm(bytes4 sel, address eOracle, address eShare, address eFee, address eRisk) internal {
        bytes memory createData = abi.encodePacked(
            type(MellowConfigLockAssertion).creationCode, abi.encode(address(vault), eOracle, eShare, eFee, eRisk)
        );
        cl.assertion(address(vault), createData, sel);
    }

    // --- Trust graph -------------------------------------------------------

    function testTrustGraphIntactPasses() public {
        _arm(MellowConfigLockAssertion.assertTrustGraphIntact.selector);
        vault.poke();
    }

    function testOracleRewiredTrips() public {
        _arm(MellowConfigLockAssertion.assertTrustGraphIntact.selector);
        vm.expectRevert(bytes("MellowConfig: oracle rewired"));
        vault.rewireOracle(evil);
    }

    function testRiskManagerRewiredTrips() public {
        _arm(MellowConfigLockAssertion.assertTrustGraphIntact.selector);
        vm.expectRevert(bytes("MellowConfig: risk manager rewired"));
        vault.rewireRiskManager(evil);
    }

    function testUncheckedFieldIgnored() public {
        // Oracle left unchecked (address(0)); rewiring it must not trip while other fields hold.
        _arm(
            MellowConfigLockAssertion.assertTrustGraphIntact.selector,
            address(0),
            shareManagerAddr,
            feeManagerAddr,
            riskManagerAddr
        );
        vault.rewireOracle(evil);
    }

    // --- Proxy implementation ----------------------------------------------

    function testProxyImplementationLockedPasses() public {
        _arm(MellowConfigLockAssertion.assertProxyImplementationLocked.selector);
        vault.poke();
    }

    function testProxyUpgradeTrips() public {
        _arm(MellowConfigLockAssertion.assertProxyImplementationLocked.selector);
        vm.expectRevert(bytes("MellowConfig: proxy implementation or admin changed"));
        vault.upgradeImplementation(evil);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("MellowConfig: zero vault"));
        new MellowConfigLockAssertion(address(0), oracleAddr, shareManagerAddr, feeManagerAddr, riskManagerAddr);
    }

    function testDeploys() public {
        MellowConfigLockAssertion assertion = new MellowConfigLockAssertion(
            address(vault), oracleAddr, shareManagerAddr, feeManagerAddr, riskManagerAddr
        );
        assertTrue(address(assertion) != address(0));
    }
}
