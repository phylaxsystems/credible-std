// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {SafeConfigLockAssertion} from "../../examples/safe/src/SafeConfigLockAssertion.sol";
import {
    SymbioticVaultCircuitBreakerAssertion,
    SymbioticVaultCircuitBreakerProtection
} from "../../examples/symbiotic/src/SymbioticVaultCircuitBreakerAssertion.sol";
import {BoringVaultAssertion} from "../../examples/veda/src/BoringVaultAssertion.sol";

contract ExampleAssertionBehaviorTest is Test {
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
        new SymbioticVaultCircuitBreakerProtection(
            address(0xA001), address(0xA002), new SymbioticVaultCircuitBreakerAssertion.LiquidationRoute[](0)
        );
    }
}
