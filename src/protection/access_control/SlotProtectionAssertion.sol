// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AccessControlBaseAssertion} from "./AccessControlBaseAssertion.sol";

/// @title SlotProtectionAssertion
/// @author Phylax Systems
/// @notice Asserts that critical storage slots on the assertion adopter are not modified
///         during the transaction.
///
/// Invariants covered:
///   - **Ownership immutability**: proxy admin, owner, sentinel, and implementation slots
///     cannot be changed outside expected governance choreography.
///   - **Timelock integrity**: delay values, proposer/executor/canceller role slots are
///     frozen so an attacker cannot shorten a delay before exploiting a governance path.
///   - **Role stability**: admin roles, operator roles, manager roles remain unchanged
///     unless an authorized governance action modifies them.
///   - **Configuration guards**: fee parameters, oracle addresses, whitelist/blocklist
///     settings, and other safety-critical configuration slots.
///
/// @dev Uses the V2 `forbidChangeForSlots` precompile which checks the transaction journal
///      for any SSTORE to the specified slots. A write is flagged even if it sets the same
///      value (conservative -- a write is suspicious regardless of whether the value changed).
///      Writes inside reverted internal calls are rolled back in the journal and do not
///      trigger a violation.
///
///      Implementers must override `_protectedSlots()` to declare which slots to protect.
///      For mapping entries (e.g., `roles[account]`), compute the slot off-chain via
///      `keccak256(abi.encode(key, mappingSlot))`.
///
///      The policy enforced is: **fail by default** on any watched-slot mutation. Protocols
///      that need conditional slot changes should use per-function triggers instead and
///      verify the change follows the expected governance path.
abstract contract SlotProtectionAssertion is AccessControlBaseAssertion {
    /// @notice Returns the storage slots that must not be modified during the transaction.
    /// @dev Override to declare the protocol-specific critical slots. Common examples:
    ///      - EIP-1967 admin slot: `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
    ///      - EIP-1967 implementation slot: `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`
    ///      - Gnosis Safe owner sentinel (slot 2), threshold (slot 4), singleton (slot 0)
    ///      - Timelock delay parameters, proposer/executor/canceller roles
    ///      - Protocol-specific admin, fee, oracle, and permission level slots
    /// @return slots Array of storage slot identifiers to protect.
    function _protectedSlots() internal pure virtual returns (bytes32[] memory slots);

    /// @notice Register the default trigger set for slot protection.
    /// @dev Uses registerTxEndTrigger so the check fires once after the transaction completes.
    ///      Call this inside your `triggers()`.
    function _registerSlotProtectionTriggers() internal view {
        registerTxEndTrigger(this.assertSlotProtection.selector);
    }

    /// @notice Verifies that none of the protected storage slots were written to during the tx.
    /// @dev Uses `ph.forbidChangeForSlots()` for a single precompile call covering all slots.
    ///      Reverts if any protected slot was modified.
    function assertSlotProtection() external {
        bytes32[] memory slots = _protectedSlots();
        require(ph.forbidChangeForSlots(slots), "AccessControl: protected slot was modified");
    }
}
