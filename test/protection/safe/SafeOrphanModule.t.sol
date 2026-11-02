// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeFixture, SafeStorageWriter} from "./SafeFixture.sol";
import {SafeConfigLockAssertion} from "../../../src/protection/safe/SafeConfigLockAssertion.sol";
import {SafeTxShapeAssertion} from "../../../src/protection/safe/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../../src/protection/safe/SafeTxShapeHelpers.sol";

contract SafeOrphanModuleTest is SafeFixture {
    address internal constant ORPHAN = address(0xBAD);

    function testConfigLockAloneAllowsPrecomputedOrphanCreationAndExecution() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            // Compute outside the monitored transaction: no mapping-key preimage is required.
            bytes32 orphanSlot = keccak256(abi.encode(ORPHAN, uint256(1)));
            _armConfig();
            assertTrue(
                _moduleCall(
                    address(writer), abi.encodeCall(SafeStorageWriter.write, (orphanSlot, bytes32(uint256(1)))), 1
                )
            );
            assertTrue(safe.isModuleEnabled(ORPHAN));
            (address[] memory listed,) = safe.getModulesPaginated(address(1), 256);
            assertEq(listed, _oneAddress(module));

            // A storage-changing action also passes the configuration assertion.
            _armConfig();
            vm.prank(ORPHAN);
            assertTrue(
                safe.execTransactionFromModule(
                    address(writer),
                    0,
                    abi.encodeCall(SafeStorageWriter.write, (bytes32(uint256(100)), bytes32(uint256(42)))),
                    1
                )
            );
            assertEq(vm.load(address(safe), bytes32(uint256(100))), bytes32(uint256(42)));
        }
    }

    function testExplicitModulePolicyBlocksBothOrphanEntrypoints() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            // PCL's single-assertion cheatcode counts proxy CALL + DELEGATECALL twice.
            // Preserve initialized storage and execute the identical upstream runtime directly.
            vm.etch(address(safe), singleton.code);
            assertTrue(
                _moduleCall(
                    address(writer),
                    abi.encodeCall(
                        SafeStorageWriter.write, (keccak256(abi.encode(ORPHAN, uint256(1))), bytes32(uint256(1)))
                    ),
                    1
                )
            );
            for (uint256 entrypoint; entrypoint < 2; ++entrypoint) {
                _armShape(SafeTxShapeAssertion.assertSafeModulePolicy.selector);
                vm.expectRevert(abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeModuleNotAllowed.selector, ORPHAN));
                vm.prank(ORPHAN);
                if (entrypoint == 0) safe.execTransactionFromModule(owner, 0, "", 0);
                else safe.execTransactionFromModuleReturnData(owner, 0, "", 0);
            }
            _armShape(SafeTxShapeAssertion.assertSafeModulePolicy.selector);
            assertTrue(_moduleCall(owner, "", 0));
        }
    }

    function testExplicitDelegatecallPolicyBlocksPrecomputedOrphanCreation() public {
        for (uint256 version; version < 4; ++version) {
            _deploy(version, address(0));
            vm.etch(address(safe), singleton.code);
            bytes32 orphanSlot = keccak256(abi.encode(ORPHAN, uint256(1)));
            _armShape(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
            vm.expectRevert(
                abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, address(writer))
            );
            _moduleCall(address(writer), abi.encodeCall(SafeStorageWriter.write, (orphanSlot, bytes32(uint256(1)))), 1);
            assertFalse(safe.isModuleEnabled(ORPHAN));
        }
    }

    function _armConfig() internal {
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
                    _oneAddress(singleton)
                )
            ),
            SafeConfigLockAssertion.assertSafeConfiguration.selector
        );
    }

    function _armShape(bytes4 check) internal {
        SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
        targets[0] = SafeTxShapeHelpers.TargetPolicy(owner, true, true, false, false);
        cl.assertion(
            address(safe),
            abi.encodePacked(
                type(SafeTxShapeAssertion).creationCode,
                abi.encode(
                    targets,
                    new SafeTxShapeHelpers.SelectorPolicy[](0),
                    new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
                    new SafeTxShapeHelpers.ApprovalPolicy[](0),
                    true,
                    _oneAddress(module)
                )
            ),
            check
        );
    }
}
