// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    RollingOutflowCircuitBreakerAssertion,
    TieredOutflowCircuitBreakerAssertion,
    SafeActionPolicyAssertion,
    SafeConfigurationLockAssertion,
    UpgradeGateStateLockAssertion,
    SettlementIntegrityPinAssertion,
    SafeTxShapeHelpers
} from "../bundles/policy-assertions.sol";

contract PolicyConstructorsTest is Test {
    function testFuzzRollingInputsAreRetained(uint256 threshold, uint256 cap, uint256 window, uint256 floor) public {
        threshold = bound(threshold, 1, 9999);
        cap = bound(cap, 0, threshold - 1);
        window = bound(window, 10, type(uint64).max);
        RollingOutflowCircuitBreakerAssertion policy =
            new RollingOutflowCircuitBreakerAssertion(address(1), threshold, window, floor, cap);
        assertEq(policy.THRESHOLD_BPS(), threshold);
        assertEq(policy.TX_CAP_BPS(), cap);
        assertEq(policy.WINDOW(), window);
        assertEq(policy.FLOOR(), floor);
    }

    function testRollingRejectsZeroToken() public {
        vm.expectRevert("Outflow breaker: token zero");
        new RollingOutflowCircuitBreakerAssertion(address(0), 100, 10, 0, 0);
    }

    function testRollingRejectsInvalidThresholds() public {
        vm.expectRevert("Outflow breaker: threshold");
        new RollingOutflowCircuitBreakerAssertion(address(1), 0, 10, 0, 0);
        vm.expectRevert("Outflow breaker: threshold");
        new RollingOutflowCircuitBreakerAssertion(address(1), 10000, 10, 0, 0);
    }

    function testRollingRejectsWindowAndCapBoundaries() public {
        vm.expectRevert("Outflow breaker: window");
        new RollingOutflowCircuitBreakerAssertion(address(1), 100, 9, 0, 0);
        vm.expectRevert("Outflow breaker: window");
        new RollingOutflowCircuitBreakerAssertion(address(1), 100, uint256(type(uint64).max) + 1, 0, 0);
        vm.expectRevert("Outflow breaker: cap");
        new RollingOutflowCircuitBreakerAssertion(address(1), 100, 10, 0, 100);
    }

    function testTieredRetainsConfiguration() public {
        TieredOutflowCircuitBreakerAssertion policy =
            new TieredOutflowCircuitBreakerAssertion(address(1), 10, 1, 9999, 1);
        assertEq(policy.TOKEN(), address(1));
        assertEq(policy.SOFT_THRESHOLD_BPS(), 1);
        assertEq(policy.HARD_THRESHOLD_BPS(), 9999);
        assertEq(policy.SOFT_WITHDRAWAL_LIMIT(), 1);
    }

    function testTieredRejectsInvalidConfiguration() public {
        vm.expectRevert("Tiered breaker: token zero");
        new TieredOutflowCircuitBreakerAssertion(address(0), 10, 1, 2, 1);
        vm.expectRevert("Tiered breaker: window");
        new TieredOutflowCircuitBreakerAssertion(address(1), 9, 1, 2, 1);
        vm.expectRevert("Tiered breaker: thresholds");
        new TieredOutflowCircuitBreakerAssertion(address(1), 10, 2, 2, 1);
        vm.expectRevert("Tiered breaker: hard threshold");
        new TieredOutflowCircuitBreakerAssertion(address(1), 10, 1, 10000, 1);
        vm.expectRevert("Tiered breaker: soft limit");
        new TieredOutflowCircuitBreakerAssertion(address(1), 10, 1, 2, 0);
    }

    function testSafeActionRequiresAdopter() public {
        vm.expectRevert("Safe policy: safe zero");
        _safeAction(address(0));
        assertEq(_safeAction(address(1)).EXPECTED_SAFE(), address(1));
    }

    function _safeAction(address safe) internal returns (SafeActionPolicyAssertion) {
        SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
        targets[0] = SafeTxShapeHelpers.TargetPolicy(address(2), true, false, false, false);
        return new SafeActionPolicyAssertion(
            safe,
            targets,
            new SafeTxShapeHelpers.SelectorPolicy[](0),
            new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
            new SafeTxShapeHelpers.ApprovalPolicy[](0),
            false,
            new address[](0)
        );
    }

    function testSafeConfigurationRequiresOwnersAndSingleton() public {
        address[] memory owners = new address[](0);
        vm.expectRevert("Safe lock: owners");
        _safeConfig(owners, address(1));
        owners = new address[](1);
        owners[0] = address(1);
        vm.expectRevert("Safe lock: singleton");
        _safeConfig(owners, address(0));
        assertEq(_safeConfig(owners, address(2)).THRESHOLD(), 1);
    }

    function _safeConfig(address[] memory owners, address singleton) internal returns (SafeConfigurationLockAssertion) {
        return
            new SafeConfigurationLockAssertion(
                owners, 1, singleton, address(0), address(0), address(0), new address[](0)
            );
    }

    function testUpgradeRequiresGateAndSelector() public {
        vm.expectRevert("Upgrade lock: config");
        _upgrade(address(0), bytes4(uint32(1)));
        vm.expectRevert("Upgrade lock: config");
        _upgrade(address(1), bytes4(0));
        assertEq(_upgrade(address(1), bytes4(uint32(1))).LOCKED_VERSION_ID(), 7);
    }

    function _upgrade(address gate, bytes4 selector) internal returns (UpgradeGateStateLockAssertion) {
        return new UpgradeGateStateLockAssertion(
            gate,
            7,
            bytes32(0),
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            bytes32(uint256(3)),
            bytes32(uint256(4)),
            selector
        );
    }

    function testSettlementRequiresSubmitSelector() public {
        vm.expectRevert("Settlement pin: submit selector");
        _settlement(bytes4(0));
        assertEq(_settlement(bytes4(uint32(1))).PROOF_OFFSET_WORD(), 2);
    }

    function _settlement(bytes4 selector) internal returns (SettlementIntegrityPinAssertion) {
        return new SettlementIntegrityPinAssertion(
            address(0),
            bytes32(0),
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            selector,
            2,
            new bytes4[](0),
            new bytes4[](0)
        );
    }
}
