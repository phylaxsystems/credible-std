// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TokenOutflowCircuitBreakerAssertion} from "../policies/token-outflow-circuit-breaker/policy.sol";
import {UpgradeGovernancePolicyAssertion} from "../policies/upgrade-governance/policy.sol";
import {SafeConfigurationPolicyAssertion} from "../policies/safe-configuration-policy/policy.sol";
import {SafeOutflowCircuitBreakerAssertion} from "../policies/safe-outflow-circuit-breaker/policy.sol";
import {SafeActionPolicyAssertion} from "../policies/safe-action-policy/policy.sol";

contract PolicyConstructorsTest is Test {
    function testBreakerRetainsConfiguration() public {
        TokenOutflowCircuitBreakerAssertion policy =
            new TokenOutflowCircuitBreakerAssertion(address(1), 100, 3600, 1e6, 0);
        assertEq(policy.TOKEN(), address(1));
        assertEq(policy.THRESHOLD_BPS(), 100);
        assertEq(policy.WINDOW(), 3600);
        assertEq(policy.MINIMUM_OUTFLOW(), 1e6);
        assertEq(policy.TRANSACTION_CAP_BPS(), 0);
    }

    function testBreakerRejectsInvalidConfiguration() public {
        vm.expectRevert("Outflow breaker: token zero");
        new TokenOutflowCircuitBreakerAssertion(address(0), 100, 10, 0, 0);
        vm.expectRevert("Outflow breaker: invalid threshold");
        new TokenOutflowCircuitBreakerAssertion(address(1), 0, 10, 0, 0);
        vm.expectRevert("Outflow breaker: invalid window");
        new TokenOutflowCircuitBreakerAssertion(address(1), 100, 9, 0, 0);
        vm.expectRevert("Outflow breaker: cap must be below threshold");
        new TokenOutflowCircuitBreakerAssertion(address(1), 100, 10, 0, 100);
    }

    function testUpgradeGovernanceRejectsZeroProxy() public {
        vm.expectRevert(UpgradeGovernancePolicyAssertion.InvalidProtectedProxy.selector);
        new UpgradeGovernancePolicyAssertion(address(0));
        new UpgradeGovernancePolicyAssertion(address(1));
    }

    function testSafeConfigurationRetainsConfiguration() public {
        address[] memory owners = new address[](1);
        owners[0] = address(1);
        SafeConfigurationPolicyAssertion policy =
            new SafeConfigurationPolicyAssertion(owners, 1, address(2), address(3), address(4));
        assertEq(policy.OWNER_COUNT(), 1);
        assertEq(policy.THRESHOLD(), 1);
        assertEq(policy.SINGLETON(), address(2));
        assertEq(policy.FALLBACK_HANDLER(), address(3));
        assertEq(policy.GUARD(), address(4));
    }

    function testSafeConfigurationRejectsInvalidConfiguration() public {
        address[] memory owners = new address[](0);
        vm.expectRevert("Safe lock: bad owners");
        new SafeConfigurationPolicyAssertion(owners, 1, address(1), address(0), address(0));
        owners = new address[](1);
        owners[0] = address(1);
        vm.expectRevert("Safe lock: singleton zero");
        new SafeConfigurationPolicyAssertion(owners, 1, address(0), address(0), address(0));
    }

    function testSafeOutflowRetainsConfiguration() public {
        SafeOutflowCircuitBreakerAssertion policy = new SafeOutflowCircuitBreakerAssertion(address(1), 86400, 1e18);
        assertEq(policy.TOKEN(), address(1));
        assertEq(policy.WINDOW(), 86400);
        assertEq(policy.LIMIT(), 1e18);
    }

    function testSafeOutflowRejectsInvalidConfiguration() public {
        vm.expectRevert("Safe breaker: token zero");
        new SafeOutflowCircuitBreakerAssertion(address(0), 10, 1);
        vm.expectRevert("Safe breaker: invalid window");
        new SafeOutflowCircuitBreakerAssertion(address(1), 9, 1);
        vm.expectRevert("Safe breaker: limit zero");
        new SafeOutflowCircuitBreakerAssertion(address(1), 10, 0);
    }

    function testSafeActionRejectsInvalidPolicyAndRetainsRules() public {
        SafeActionPolicyAssertion.CallRule[] memory invalidRules = new SafeActionPolicyAssertion.CallRule[](1);
        invalidRules[0] = SafeActionPolicyAssertion.CallRule(address(2), bytes4(0x12345678), type(uint256).max);
        vm.expectRevert(SafeActionPolicyAssertion.SafeActionPolicyInvalidPolicy.selector);
        new SafeActionPolicyAssertion(
            new address[](0),
            new address[](0),
            invalidRules,
            new SafeActionPolicyAssertion.ArgPin[](0),
            new SafeActionPolicyAssertion.ApprovalCap[](0),
            0
        );

        SafeActionPolicyAssertion.CallRule[] memory rules = new SafeActionPolicyAssertion.CallRule[](1);
        rules[0] = SafeActionPolicyAssertion.CallRule(address(2), bytes4(0x12345678), 0);
        SafeActionPolicyAssertion policy = new SafeActionPolicyAssertion(
            new address[](0),
            new address[](0),
            rules,
            new SafeActionPolicyAssertion.ArgPin[](0),
            new SafeActionPolicyAssertion.ApprovalCap[](0),
            1 ether
        );
        (bool allowed, uint256 maxValue) = policy.ruleFor(address(2), bytes4(0x12345678));
        assertTrue(allowed);
        assertEq(maxValue, 0);
        assertEq(policy.MAX_ETH_PER_TX(), 1 ether);
    }
}
