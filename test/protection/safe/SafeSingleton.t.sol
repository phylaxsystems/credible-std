// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeFixture, SafeStorageWriter} from "./SafeFixture.sol";
import {SafeConfigLockAssertion} from "../../../src/protection/safe/SafeConfigLockAssertion.sol";

contract SafeSingletonTest is SafeFixture {
    function testReplacementBlockedOnSupportedSafes() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            address replacement = address(uint160(0x1000 + version));
            vm.etch(replacement, singleton.code);
            _arm();
            vm.expectRevert(bytes("SafeConfigLock: singleton changed"));
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
            _arm();
            vm.expectRevert(bytes("SafeConfigLock: singleton changed"));
            _moduleCall(address(writer), abi.encodeCall(SafeStorageWriter.replaceAndRestore, (replacement)), 1);
        }
    }

    function testActiveLockBlocksRealVersionUpgrade() public {
        for (uint256 version; version < 3; ++version) {
            _deploy(version, address(0));
            address replacement = deployCode("lib/safe-smart-account-1.5.0/contracts/Safe.sol:Safe");
            string memory originalVersion = safe.VERSION();
            assertTrue(singleton.codehash != replacement.codehash);
            _arm();
            vm.expectRevert(bytes("SafeConfigLock: singleton changed"));
            _ownerCall(
                address(writer),
                abi.encodeCall(SafeStorageWriter.write, (bytes32(0), bytes32(uint256(uint160(replacement))))),
                1
            );
            assertEq(address(uint160(uint256(vm.load(address(safe), bytes32(0))))), singleton);
            assertEq(safe.VERSION(), originalVersion);
            _arm();
            assertTrue(_ownerCall(owner, "", 0));
        }
    }

    function testEntireSingletonSlotIsProtected() public {
        _deploy(2, address(0));
        bytes32 original = vm.load(address(safe), bytes32(0));
        // Keep the implementation address unchanged, but change the upper slot bits.
        bytes32 replacement = original | bytes32(uint256(1) << 255);
        _arm();
        vm.expectRevert(bytes("SafeConfigLock: singleton changed"));
        _ownerCall(address(writer), abi.encodeCall(SafeStorageWriter.write, (bytes32(0), replacement)), 1);
        assertEq(vm.load(address(safe), bytes32(0)), original);
    }

    function testOrdinaryOwnerExecutionOnSupportedSafes() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            _arm();
            assertTrue(_ownerCall(owner, "", 0));
        }
    }

    function testWritingSameSingletonValueIsAllowed() public {
        _deploy(2, address(0));
        bytes32 original = vm.load(address(safe), bytes32(0));
        _arm();
        assertTrue(_ownerCall(address(writer), abi.encodeCall(SafeStorageWriter.write, (bytes32(0), original)), 1));
        assertEq(vm.load(address(safe), bytes32(0)), original);
    }

    function _arm() internal {
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
                    address(0)
                )
            ),
            SafeConfigLockAssertion.assertSafeConfiguration.selector
        );
    }
}
