// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

interface ISafeConfigLockTarget {
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
}

/// @title SafeConfigLockHelpers
/// @author Phylax Systems
/// @notice Shared constants and snapshot readers for Safe configuration assertions.
abstract contract SafeConfigLockHelpers is Assertion {
    address internal constant SPEC_RECORDER = address(uint160(uint256(keccak256("SpecRecorder"))));
    address internal constant SENTINEL_MODULES = address(0x1);

    uint256 internal constant MODULE_PAGE_SIZE = 256;

    bytes32 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    bytes32 internal constant MODULE_GUARD_STORAGE_SLOT =
        0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    /// @notice Computes the deterministic hash used by owner and module allow lists.
    /// @dev Sorts the provided addresses in memory before hashing, so Safe linked-list order
    ///      does not affect the resulting set hash.
    function hashAddressSet(address[] memory accounts) public pure returns (bytes32) {
        _sortAddresses(accounts);
        return keccak256(abi.encode(accounts));
    }

    function _ownersAt(address safe, PhEvm.ForkId memory fork) internal view returns (address[] memory owners) {
        owners = abi.decode(_viewAt(safe, abi.encodeCall(ISafeConfigLockTarget.getOwners, ()), fork), (address[]));
    }

    function _thresholdAt(address safe, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(safe, abi.encodeCall(ISafeConfigLockTarget.getThreshold, ()), fork);
    }

    function _modulesAt(address safe, PhEvm.ForkId memory fork) internal view returns (address[] memory modules) {
        address next;
        (modules, next) = abi.decode(
            _viewAt(
                safe,
                abi.encodeCall(ISafeConfigLockTarget.getModulesPaginated, (SENTINEL_MODULES, MODULE_PAGE_SIZE)),
                fork
            ),
            (address[], address)
        );
        require(next == SENTINEL_MODULES, "SafeConfigLock: too many modules");
    }

    function _guardAt(address safe, PhEvm.ForkId memory fork) internal view returns (address) {
        return _addressSlotAt(safe, GUARD_STORAGE_SLOT, fork);
    }

    function _moduleGuardAt(address safe, PhEvm.ForkId memory fork) internal view returns (address) {
        return _addressSlotAt(safe, MODULE_GUARD_STORAGE_SLOT, fork);
    }

    function _fallbackHandlerAt(address safe, PhEvm.ForkId memory fork) internal view returns (address) {
        return _addressSlotAt(safe, FALLBACK_HANDLER_STORAGE_SLOT, fork);
    }

    function _addressSlotAt(address safe, bytes32 slot, PhEvm.ForkId memory fork) internal view returns (address) {
        return address(uint160(uint256(ph.loadStateAt(safe, slot, fork))));
    }

    function _isApprovedHash(bytes32 actualHash, bytes32[] storage approvedHashes, bool emptySet)
        internal
        view
        returns (bool)
    {
        for (uint256 i; i < approvedHashes.length; ++i) {
            if (approvedHashes[i] == actualHash) {
                return true;
            }

            if (emptySet && approvedHashes[i] == bytes32(0)) {
                return true;
            }
        }

        return false;
    }

    function _sortAddresses(address[] memory accounts) internal pure {
        for (uint256 i = 1; i < accounts.length; ++i) {
            address current = accounts[i];
            uint256 j = i;

            while (j > 0 && uint160(accounts[j - 1]) > uint160(current)) {
                accounts[j] = accounts[j - 1];
                --j;
            }

            accounts[j] = current;
        }
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "SafeConfigLock: safe view failed";
    }

    function _registerReshiramSpec() internal {
        (bool ok,) = SPEC_RECORDER.call(
            abi.encodeWithSelector(bytes4(keccak256("registerAssertionSpec(uint8)")), AssertionSpec.Reshiram)
        );
        require(ok, "SafeConfigLock: spec registration failed");
    }
}
