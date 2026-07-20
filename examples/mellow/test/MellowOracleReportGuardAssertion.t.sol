// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {MellowOracleReportGuardAssertion} from "../src/MellowOracleReportGuardAssertion.sol";
import {IMellowOracle} from "../src/MellowCuratorInterfaces.sol";
import {MockMellowOracle} from "./MellowMocks.sol";

contract MellowOracleReportGuardAssertionTest is Test, CredibleTest {
    MockMellowOracle internal oracle;
    address internal asset = makeAddr("asset");

    function setUp() public {
        oracle = new MockMellowOracle();
        oracle.addAsset(asset);
        oracle.setReport(asset, 1e18, false); // baseline price-per-share
    }

    function _arm(bytes4 sel, uint256 maxDriftBps) internal {
        bytes memory createData = abi.encodePacked(
            type(MellowOracleReportGuardAssertion).creationCode, abi.encode(address(oracle), maxDriftBps)
        );
        cl.assertion(address(oracle), createData, sel);
    }

    function _report(address asset_, uint224 priceD18) internal pure returns (IMellowOracle.Report[] memory reports) {
        reports = new IMellowOracle.Report[](1);
        reports[0] = IMellowOracle.Report(asset_, priceD18);
    }

    // --- Honest paths ------------------------------------------------------

    function retiredOracleCapWithinCapPasses() public {
        // +20% move under a 50% catastrophe cap.
        _arm(MellowOracleReportGuardAssertion.assertReportDriftWithinCap.selector, 5_000);
        oracle.submitReports(_report(asset, 1.2e18));
    }

    function retiredOracleCapModestNegativeMovePasses() public {
        // A real -10% repricing (e.g. mild slashing) is well within the 50% cap.
        _arm(MellowOracleReportGuardAssertion.assertReportDriftWithinCap.selector, 5_000);
        oracle.submitReports(_report(asset, 0.9e18));
    }

    function retiredOracleCapBootstrapReportSkipped() public {
        // A freshly supported asset has no prior price; its first report does not reprice the vault.
        address fresh = makeAddr("freshAsset");
        oracle.addAsset(fresh);
        _arm(MellowOracleReportGuardAssertion.assertReportDriftWithinCap.selector, 100); // tight cap
        oracle.submitReports(_report(fresh, 5e18));
    }

    function retiredOracleCapSuspiciousReportCannotBypassImmutableCap() public {
        // A suspicious report can later be accepted and propagated, so the immutable cap applies
        // when it is first stored.
        oracle.setNextSuspicious(true);
        _arm(MellowOracleReportGuardAssertion.assertReportDriftWithinCap.selector, 100); // tight cap
        vm.expectRevert(bytes("MellowOracle: report price drift exceeds cap"));
        oracle.submitReports(_report(asset, 0.4e18)); // -60% but suspicious
    }

    // --- Malicious path ----------------------------------------------------

    function retiredOracleCapDriftExceedsCapTrips() public {
        // Stolen key (having widened the mutable securityParams) reprices toward zero: -60% > 50% cap.
        _arm(MellowOracleReportGuardAssertion.assertReportDriftWithinCap.selector, 5_000);
        vm.expectRevert(bytes("MellowOracle: report price drift exceeds cap"));
        oracle.submitReports(_report(asset, 0.4e18));
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroOracle() public {
        vm.expectRevert(bytes("MellowOracle: zero oracle"));
        new MellowOracleReportGuardAssertion(address(0), 5_000);
    }

    function testRejectsZeroDriftCap() public {
        vm.expectRevert(bytes("MellowOracle: invalid drift cap"));
        new MellowOracleReportGuardAssertion(address(oracle), 0);
    }

    function testDeploys() public {
        MellowOracleReportGuardAssertion assertion = new MellowOracleReportGuardAssertion(address(oracle), 5_000);
        assertTrue(address(assertion) != address(0));
    }
}
