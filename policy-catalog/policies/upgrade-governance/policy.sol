// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {AccessControlBaseAssertion} from "credible-std/protection/access_control/AccessControlBaseAssertion.sol";
import {SlotProtectionAssertion} from "credible-std/protection/access_control/SlotProtectionAssertion.sol";

/// @title UpgradeGovernancePolicyAssertion
/// @author Phylax Systems
/// @notice Requires governance to replace or disable the active assertion release before changing
///         the protected proxy implementation.
/// @dev Protects the EIP-1967 implementation slot on one adopter. This assertion does not inspect
///      finality, priority-request accounting, desert mode, Safe actions, or bridge outflows.
contract UpgradeGovernancePolicyAssertion is SlotProtectionAssertion {
    error InvalidProtectedProxy();

    /// @notice EIP-1967 implementation slot, `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address protectedProxy_) AccessControlBaseAssertion(protectedProxy_) {
        if (protectedProxy_ == address(0)) revert InvalidProtectedProxy();
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers one storage-change trigger for the proxy implementation slot.
    function triggers() external view override {
        _registerSlotProtectionTriggers();
    }

    function _protectedSlots() internal pure override returns (bytes32[] memory slots) {
        slots = new bytes32[](1);
        slots[0] = EIP1967_IMPLEMENTATION_SLOT;
    }
}
