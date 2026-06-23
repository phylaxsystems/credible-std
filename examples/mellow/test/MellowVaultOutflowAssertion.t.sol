// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {MellowVaultOutflowAssertion} from "../src/MellowVaultOutflowAssertion.sol";
import {MockERC20} from "./MellowMocks.sol";

contract MellowVaultOutflowAssertionTest is Test, CredibleTest {
    MockERC20 internal asset;
    address internal vault = makeAddr("vault");

    function setUp() public {
        asset = new MockERC20();
    }

    /// @dev The `watchCumulativeOutflow` trigger that fires the breaker live is driven by the
    ///      executor's rolling-window accounting and is not simulated by local `pcl test`, so the
    ///      breaker's hard-revert decision is validated by calling it directly rather than through
    ///      an armed `cl.assertion` transaction. Honest in-window flow is calibration, not logic.
    function testBreakerRevertsWhenInvoked() public {
        MellowVaultOutflowAssertion assertion = new MellowVaultOutflowAssertion(vault, address(asset), 2_000, 1 days);
        vm.expectRevert(bytes("MellowOutflow: vault asset outflow circuit breaker tripped"));
        assertion.assertOutflowWithinLimit();
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("MellowOutflow: zero vault"));
        new MellowVaultOutflowAssertion(address(0), address(asset), 2_000, 1 days);
    }

    function testRejectsZeroAsset() public {
        vm.expectRevert(bytes("MellowOutflow: zero asset"));
        new MellowVaultOutflowAssertion(vault, address(0), 2_000, 1 days);
    }

    function testRejectsZeroThreshold() public {
        vm.expectRevert(bytes("MellowOutflow: bad threshold"));
        new MellowVaultOutflowAssertion(vault, address(asset), 0, 1 days);
    }

    function testRejectsThresholdAboveFull() public {
        vm.expectRevert(bytes("MellowOutflow: bad threshold"));
        new MellowVaultOutflowAssertion(vault, address(asset), 10_001, 1 days);
    }

    function testRejectsZeroWindow() public {
        vm.expectRevert(bytes("MellowOutflow: zero window"));
        new MellowVaultOutflowAssertion(vault, address(asset), 2_000, 0);
    }

    function testDeploys() public {
        MellowVaultOutflowAssertion assertion = new MellowVaultOutflowAssertion(vault, address(asset), 2_000, 1 days);
        assertTrue(address(assertion) != address(0));
    }
}
