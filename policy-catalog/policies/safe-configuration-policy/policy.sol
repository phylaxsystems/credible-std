// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {SafeConfigLockHelpers} from "credible-std/protection/safe/SafeConfigLockHelpers.sol";

/// @title SafeConfigurationPolicyAssertion
/// @notice A Safe ends every transaction with the signers, threshold and plumbing it started
///         the package with.
/// @dev Adopted by each Safe. Who can sign, how many must sign, and which code runs behind the
///      Safe are what every other assertion relies on. Pinned exactly, not as a minimum:
///      - the owner set (any order) and the threshold;
///      - no modules, since a module executes without signatures and outside the action policy;
///      - the transaction guard, the module guard (Safe 1.5.0) and the fallback handler;
///      - the singleton in storage slot 0, which a delegatecall could otherwise rewrite.
///      It runs at transaction end on every transaction that writes the Safe's storage, which is
///      every executed Safe transaction (the nonce moves), whatever path made the change. Rotating a
///      signer or installing a guard follows the agreed flow: disable, change, re-enable with the new
///      configuration.
contract SafeConfigurationPolicyAssertion is SafeConfigLockHelpers {
    bytes32 public immutable OWNER_SET_HASH;
    uint256 public immutable OWNER_COUNT;
    uint256 public immutable THRESHOLD;
    address public immutable SINGLETON;
    address public immutable FALLBACK_HANDLER;
    address public immutable GUARD;

    constructor(address[] memory owners, uint256 threshold, address singleton, address fallbackHandler, address guard) {
        require(owners.length != 0 && threshold != 0 && threshold <= owners.length, "Safe lock: bad owners");
        require(singleton != address(0), "Safe lock: singleton zero");
        OWNER_SET_HASH = hashAddressSet(owners);
        OWNER_COUNT = owners.length;
        THRESHOLD = threshold;
        SINGLETON = singleton;
        FALLBACK_HANDLER = fallbackHandler;
        GUARD = guard;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.assertionSafeConfigUnchanged.selector);
    }

    /// @notice The Safe's configuration at transaction end is the pinned one.
    /// - A failure names the part that moved: owners, threshold, modules, guard, fallback handler or
    ///   singleton.
    function assertionSafeConfigUnchanged() external view {
        address safe = ph.getAssertionAdopter();
        PhEvm.ForkId memory post = _postTx();

        // First: every other read below runs the singleton's code, which a new singleton controls.
        require(_addressSlotAt(safe, bytes32(0), post) == SINGLETON, "Safe: singleton changed");
        address[] memory owners = _ownersAt(safe, post);
        require(owners.length == OWNER_COUNT && hashAddressSet(owners) == OWNER_SET_HASH, "Safe: owner set changed");
        require(_thresholdAt(safe, post) == THRESHOLD, "Safe: threshold changed");
        require(_modulesAt(safe, post).length == 0, "Safe: module enabled");
        require(_guardAt(safe, post) == GUARD, "Safe: guard changed");
        require(_moduleGuardAt(safe, post) == address(0), "Safe: module guard set");
        require(_fallbackHandlerAt(safe, post) == FALLBACK_HANDLER, "Safe: fallback handler changed");
    }
}
