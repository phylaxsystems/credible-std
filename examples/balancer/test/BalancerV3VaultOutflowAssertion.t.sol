// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {BalancerV3VaultOutflowAssertion} from "../src/BalancerV3VaultOutflowAssertion.sol";

contract BalancerV3VaultOutflowAssertionTest is Test, CredibleTest {
    address internal vault = makeAddr("vault");
    address internal token = makeAddr("token");

    /// @dev The `watchCumulativeOutflow` trigger is driven by the executor's rolling-window
    ///      accounting and is not simulated by local `pcl test`, so the breaker's hard-revert
    ///      decision is validated by calling it directly rather than through an armed
    ///      `cl.assertion` transaction. Honest in-window flow is calibration, not logic.
    function testBreakerRevertsWhenInvoked() public {
        BalancerV3VaultOutflowAssertion assertion = new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 1 days);
        vm.expectRevert(bytes("BalancerV3Outflow: vault token outflow circuit breaker tripped"));
        assertion.assertOutflowWithinLimit();
    }

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("BalancerV3Outflow: zero vault"));
        new BalancerV3VaultOutflowAssertion(address(0), token, 2_000, 1 days);
    }

    function testRejectsZeroToken() public {
        vm.expectRevert(bytes("BalancerV3Outflow: zero token"));
        new BalancerV3VaultOutflowAssertion(vault, address(0), 2_000, 1 days);
    }

    function testRejectsZeroThreshold() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad threshold"));
        new BalancerV3VaultOutflowAssertion(vault, token, 0, 1 days);
    }

    function testRejectsThresholdAboveFull() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad threshold"));
        new BalancerV3VaultOutflowAssertion(vault, token, 10_001, 1 days);
    }

    function testRejectsZeroWindow() public {
        vm.expectRevert(bytes("BalancerV3Outflow: zero window"));
        new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 0);
    }

    function testDeploys() public {
        BalancerV3VaultOutflowAssertion assertion = new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 1 days);
        assertTrue(address(assertion) != address(0));
    }
}
