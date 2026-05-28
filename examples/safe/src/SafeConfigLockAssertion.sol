// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {SafeConfigLockHelpers} from "./SafeConfigLockHelpers.sol";

/// @title SafeConfigLockAssertion
/// @author Phylax Systems
/// @notice Locks the critical configuration envelope for a Safe multisig.
/// @dev The assertion checks the Safe after each monitored transaction:
///      - threshold and owner count stay above configured minimums;
///      - owner and module sets match one of the approved set hashes;
///      - transaction guard, module guard, and fallback handler match expected addresses.
///
///      Address set hashes are computed by sorting addresses ascending and then hashing
///      `abi.encode(sortedAddresses)`. For modules, `bytes32(0)` in the approved hash list
///      is a sentinel meaning "modules must be disabled".
contract SafeConfigLockAssertion is SafeConfigLockHelpers {
    uint256 public immutable minThreshold;
    uint256 public immutable minOwners;
    address public immutable expectedGuard;
    address public immutable expectedModuleGuard;
    address public immutable expectedFallbackHandler;

    bytes32[] public approvedOwnerSetHashes;
    bytes32[] public approvedModuleSetHashes;

    constructor(
        uint256 minThreshold_,
        uint256 minOwners_,
        bytes32[] memory approvedOwnerSetHashes_,
        bytes32[] memory approvedModuleSetHashes_,
        address expectedGuard_,
        address expectedModuleGuard_,
        address expectedFallbackHandler_
    ) {
        require(approvedOwnerSetHashes_.length != 0, "SafeConfigLock: owner hashes empty");
        require(approvedModuleSetHashes_.length != 0, "SafeConfigLock: module hashes empty");

        minThreshold = minThreshold_;
        minOwners = minOwners_;
        expectedGuard = expectedGuard_;
        expectedModuleGuard = expectedModuleGuard_;
        expectedFallbackHandler = expectedFallbackHandler_;

        for (uint256 i; i < approvedOwnerSetHashes_.length; ++i) {
            approvedOwnerSetHashes.push(approvedOwnerSetHashes_[i]);
        }

        for (uint256 i; i < approvedModuleSetHashes_.length; ++i) {
            approvedModuleSetHashes.push(approvedModuleSetHashes_[i]);
        }

        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.assertSafeConfiguration.selector);
    }

    /// @notice Checks the Safe config after the triggering transaction has completed.
    /// @dev Fails when a Safe transaction leaves owners, modules, guards, or fallback handling
    ///      outside the deployment-time policy. A zero module-set hash in the approved list
    ///      only approves the empty module set.
    function assertSafeConfiguration() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.ForkId memory post = _postTx();

        address[] memory owners = _ownersAt(safe, post);
        uint256 threshold = _thresholdAt(safe, post);

        require(threshold >= minThreshold, "SafeConfigLock: threshold below minimum");
        require(owners.length >= minOwners, "SafeConfigLock: owner count below minimum");
        require(
            _isApprovedHash(hashAddressSet(owners), approvedOwnerSetHashes, false),
            "SafeConfigLock: owner set not approved"
        );

        address[] memory modules = _modulesAt(safe, post);
        require(
            _isApprovedHash(hashAddressSet(modules), approvedModuleSetHashes, modules.length == 0),
            "SafeConfigLock: module set not approved"
        );

        require(_guardAt(safe, post) == expectedGuard, "SafeConfigLock: guard mismatch");
        require(_moduleGuardAt(safe, post) == expectedModuleGuard, "SafeConfigLock: module guard mismatch");
        require(_fallbackHandlerAt(safe, post) == expectedFallbackHandler, "SafeConfigLock: fallback handler mismatch");
    }

    function approvedOwnerSetHashCount() external view returns (uint256) {
        return approvedOwnerSetHashes.length;
    }

    function approvedModuleSetHashCount() external view returns (uint256) {
        return approvedModuleSetHashes.length;
    }
}
