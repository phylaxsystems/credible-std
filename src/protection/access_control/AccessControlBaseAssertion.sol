// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";

/// @title AccessControlBaseAssertion
/// @author Phylax Systems
/// @notice Base contract for access-control assertions (V2 syntax).
/// @dev Provides the protected target address and shared helpers for the access-control suite.
///      Inherit from this (and one or more invariant contracts), then implement `triggers()`.
///
/// Example -- combine slot protection and balance conservation:
/// ```solidity
/// contract MyProtocolGuard is SlotProtectionAssertion, BalanceConservationAssertion {
///     constructor(address _target)
///         AccessControlBaseAssertion(_target)
///     {}
///
///     function _protectedSlots() internal pure override returns (bytes32[] memory) { ... }
///     function _conservedBalances() internal view override returns (ConservedBalance[] memory) { ... }
///
///     function triggers() external view override {
///         _registerSlotProtectionTriggers();
///         _registerBalanceConservationTriggers();
///     }
/// }
/// ```
abstract contract AccessControlBaseAssertion is Assertion {
    /// @notice The contract whose access control is being protected (assertion adopter).
    address internal immutable target;

    constructor(address _target) {
        target = _target;
    }
}
