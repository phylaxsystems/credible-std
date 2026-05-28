// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {AssertionSpec} from "../../SpecRecorder.sol";

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
    address internal constant SENTINEL_MODULES = address(0x1);

    uint256 internal constant MODULE_PAGE_SIZE = 256;
    uint64 internal constant MODULE_PAGE_VIEW_GAS = 2_000_000;

    bytes32 internal constant FALLBACK_HANDLER_STORAGE_SLOT =
        0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    bytes32 internal constant MODULE_GUARD_STORAGE_SLOT =
        0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    /// @notice Computes the deterministic hash used by owner and module allow lists.
    /// @dev Sorts a copy before hashing, so Safe linked-list order does not affect the
    ///      resulting set hash and the caller's memory array is left unchanged.
    function hashAddressSet(address[] memory accounts) public pure returns (bytes32) {
        address[] memory sorted = new address[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
            sorted[i] = accounts[i];
        }

        _sortAddresses(sorted);
        return keccak256(abi.encode(sorted));
    }

    function _ownersAt(address safe, PhEvm.ForkId memory fork) internal view returns (address[] memory owners) {
        owners = abi.decode(_viewAt(safe, abi.encodeCall(ISafeConfigLockTarget.getOwners, ()), fork), (address[]));
    }

    function _thresholdAt(address safe, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(safe, abi.encodeCall(ISafeConfigLockTarget.getThreshold, ()), fork);
    }

    function _modulesAt(address safe, PhEvm.ForkId memory fork) internal view returns (address[] memory modules) {
        address next = SENTINEL_MODULES;
        while (true) {
            PhEvm.StaticCallResult memory result = ph.staticcallAt(
                safe,
                abi.encodeCall(ISafeConfigLockTarget.getModulesPaginated, (next, MODULE_PAGE_SIZE)),
                MODULE_PAGE_VIEW_GAS,
                fork
            );
            require(result.ok, _viewFailureMessage());

            (address[] memory page, address pageNext) = abi.decode(result.data, (address[], address));

            modules = _appendAddresses(modules, page);
            if (pageNext == SENTINEL_MODULES) return modules;
            next = pageNext;
        }
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
        if (accounts.length < 2) return;
        _quickSortAddresses(accounts, 0, accounts.length - 1);
    }

    function _quickSortAddresses(address[] memory accounts, uint256 left, uint256 right) private pure {
        uint256 i = left;
        uint256 j = right;
        uint160 pivot = uint160(accounts[left + (right - left) / 2]);

        while (i <= j) {
            while (uint160(accounts[i]) < pivot) {
                ++i;
            }
            while (uint160(accounts[j]) > pivot) {
                if (j == 0) break;
                --j;
            }

            if (i <= j) {
                (accounts[i], accounts[j]) = (accounts[j], accounts[i]);
                ++i;
                if (j == 0) break;
                --j;
            }
        }

        if (left < j) _quickSortAddresses(accounts, left, j);
        if (i < right) _quickSortAddresses(accounts, i, right);
    }

    function _appendAddresses(address[] memory left, address[] memory right)
        private
        pure
        returns (address[] memory combined)
    {
        combined = new address[](left.length + right.length);
        for (uint256 i; i < left.length; ++i) {
            combined[i] = left[i];
        }
        for (uint256 i; i < right.length; ++i) {
            combined[left.length + i] = right[i];
        }
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "SafeConfigLock: safe view failed";
    }

    function _registerReshiramSpec() internal {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }
}
