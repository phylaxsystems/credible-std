// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeFixture, SafeStorageWriter} from "./SafeFixture.sol";
import {SafeConfigLockAssertion} from "../../../src/protection/safe/SafeConfigLockAssertion.sol";

contract SafeSingletonTest is SafeFixture {
    function testUnapprovedReplacementBlockedOnSupportedSafes() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            address replacement = address(uint160(0x1000 + version));
            vm.etch(replacement, singleton.code);
            _arm(_oneAddress(singleton));
            vm.expectRevert(bytes("SafeConfigLock: singleton not approved"));
            _moduleCall(
                address(writer),
                abi.encodeCall(SafeStorageWriter.write, (bytes32(0), bytes32(uint256(uint160(replacement))))),
                1
            );
            assertEq(address(uint160(uint256(vm.load(address(safe), bytes32(0))))), singleton);
        }
    }

    function testTransientReplacementBlockedOnSupportedSafes() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            address replacement = address(uint160(0x1000 + version));
            vm.etch(replacement, singleton.code);
            _arm(_oneAddress(singleton));
            vm.expectRevert(bytes("SafeConfigLock: singleton not approved"));
            _moduleCall(address(writer), abi.encodeCall(SafeStorageWriter.replaceAndRestore, (replacement)), 1);
        }
    }

    function testExplicitlyApprovedUpgradeOnSupportedSafes() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            address replacement = address(uint160(0x1000 + version));
            vm.etch(replacement, singleton.code);
            address[] memory implementations = new address[](2);
            implementations[0] = singleton;
            implementations[1] = replacement;
            _arm(implementations);
            assertTrue(
                _ownerCall(
                    address(writer),
                    abi.encodeCall(SafeStorageWriter.write, (bytes32(0), bytes32(uint256(uint160(replacement))))),
                    1
                )
            );
            assertEq(address(uint160(uint256(vm.load(address(safe), bytes32(0))))), replacement);
        }
    }

    function testOrdinaryOwnerExecutionOnSupportedSafes() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            _arm(_oneAddress(singleton));
            assertTrue(_ownerCall(owner, "", 0));
        }
    }

    function _arm(address[] memory implementations) internal {
        cl.assertion(
            address(safe),
            abi.encodePacked(
                type(SafeConfigLockAssertion).creationCode,
                abi.encode(
                    1,
                    1,
                    _oneHash(keccak256(abi.encode(_oneAddress(owner)))),
                    _oneHash(keccak256(abi.encode(_oneAddress(module)))),
                    address(0),
                    address(0),
                    address(0),
                    implementations
                )
            ),
            SafeConfigLockAssertion.assertSafeConfiguration.selector
        );
    }
}
