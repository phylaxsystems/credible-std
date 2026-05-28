// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../src/CredibleTest.sol";
import {SafeConfigLockAssertion} from "../../examples/safe/src/SafeConfigLockAssertion.sol";
import {SafeTxShapeAssertion} from "../../examples/safe/src/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../examples/safe/src/SafeTxShapeHelpers.sol";
import {SymbioticVaultAssertion} from "../../examples/symbiotic/src/SymbioticVaultAssertion.sol";
import {SymbioticVaultCircuitBreakerAssertion} from "../../examples/symbiotic/src/SymbioticVaultCircuitBreakerAssertion.sol";
import {SymbioticVaultConfigAssertion} from "../../examples/symbiotic/src/SymbioticVaultConfigAssertion.sol";
import {BoringVaultAssertion} from "../../examples/veda/src/BoringVaultAssertion.sol";

contract MockSafe {
    function execTransaction(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address,
        bytes calldata
    ) external pure returns (bool success) {
        return true;
    }
}

contract ExampleAssertionBehaviorTest is Test, CredibleTest {
    MockSafe internal safe;
    address internal allowedTarget = address(0xA110);
    address internal blockedTarget = address(0xB10C);

    function setUp() external {
        safe = new MockSafe();
    }

    function testSafeTxShapeAssertionAllowsConfiguredTarget() external {
        cl.assertion(
            address(safe),
            abi.encodePacked(type(SafeTxShapeAssertion).creationCode, _safeTxShapeConstructorArgs()),
            _selector("assertSafeTargetSelectorPolicy()")
        );

        assertTrue(_execSafeTx(allowedTarget, abi.encodeWithSelector(bytes4(0x12345678)), 0));
    }

    function testSafeTxShapeAssertionBlocksUnknownTarget() external {
        cl.assertion(
            address(safe),
            abi.encodePacked(type(SafeTxShapeAssertion).creationCode, _safeTxShapeConstructorArgs()),
            _selector("assertSafeTargetSelectorPolicy()")
        );

        vm.expectRevert(abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeUnknownTarget.selector, blockedTarget));
        _execSafeTx(blockedTarget, abi.encodeWithSelector(bytes4(0x12345678)), 0);
    }

    function testSafeConfigHashIgnoresOwnerOrdering() external {
        bytes32[] memory ownerHashes = new bytes32[](1);
        bytes32[] memory moduleHashes = new bytes32[](1);
        SafeConfigLockAssertion config =
            new SafeConfigLockAssertion(2, 3, ownerHashes, moduleHashes, address(0), address(0), address(0));

        address[] memory owners = new address[](3);
        owners[0] = address(0x3003);
        owners[1] = address(0x3001);
        owners[2] = address(0x3002);

        address[] memory sameOwnersDifferentOrder = new address[](3);
        sameOwnersDifferentOrder[0] = owners[2];
        sameOwnersDifferentOrder[1] = owners[0];
        sameOwnersDifferentOrder[2] = owners[1];

        assertEq(config.hashAddressSet(owners), config.hashAddressSet(sameOwnersDifferentOrder));
    }

    function testBoringVaultConstructorRequiresMonitoredAssets() external {
        vm.expectRevert(bytes("BoringVault: no monitored assets"));
        new BoringVaultAssertion(address(0xA001), address(0xA002), 18, new address[](0), 100, 100, 1_000, 1_000, 1 days);
    }

    function testSymbioticCircuitBreakerRequiresLiquidationRoutes() external {
        vm.expectRevert(bytes("SymbioticCircuitBreaker: missing liquidation routes"));
        new SymbioticVaultAssertion(
            address(0xA001),
            address(0xA002),
            _symbioticPolicy(),
            new SymbioticVaultCircuitBreakerAssertion.LiquidationRoute[](0)
        );
    }

    function _execSafeTx(address to, bytes memory data, uint8 operation) internal returns (bool) {
        return safe.execTransaction(to, 0, data, operation, 0, 0, 0, address(0), address(0), "");
    }

    function _safeTxShapeConstructorArgs() internal view returns (bytes memory) {
        return abi.encode(
            _targetPolicies(),
            new SafeTxShapeHelpers.SelectorPolicy[](0),
            new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
            new SafeTxShapeHelpers.ApprovalPolicy[](0),
            false,
            new address[](0)
        );
    }

    function _targetPolicies() internal view returns (SafeTxShapeHelpers.TargetPolicy[] memory policies) {
        policies = new SafeTxShapeHelpers.TargetPolicy[](1);
        policies[0] = SafeTxShapeHelpers.TargetPolicy({
            target: allowedTarget,
            allowAnySelector: true,
            allowEmptyCalldata: false,
            allowFallbackCalldata: false,
            allowNonzeroValue: false
        });
    }

    function _symbioticPolicy() internal pure returns (SymbioticVaultConfigAssertion.VaultConfigPolicy memory) {
        return SymbioticVaultConfigAssertion.VaultConfigPolicy({
            requireCompleteInitialization: false,
            requireSlasher: false,
            requireDelegatorVaultMatch: false,
            requireSlasherVaultMatch: false,
            requireBurnerWhenSlasherHooked: false,
            minEpochDuration: 0,
            maxEpochDuration: 0,
            minVetoExecutionWindow: 0,
            minResolverSetEpochsDelay: 0
        });
    }

    function _selector(string memory signature) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(signature)));
    }
}
