// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";
import {TriggerRecorder} from "./TriggerRecorder.sol";
import {SpecRecorder, AssertionSpec} from "./SpecRecorder.sol";
import {StateChanges} from "./StateChanges.sol";

/// @title Assertion
/// @author Phylax Systems
/// @notice Base contract for creating Credible Layer assertions
/// @dev Inherit from this contract to create custom assertions. Assertions can inspect
/// transaction state via the inherited `ph` precompile and register triggers to specify
/// when the assertion should be executed.
///
/// Example:
/// ```solidity
/// contract MyAssertion is Assertion {
///     function triggers() external view override {
///         registerCallTrigger(this.checkInvariant.selector, ITarget.deposit.selector);
///     }
///
///     function checkInvariant() external {
///         ph.forkPostTx();
///         // Check invariants...
///     }
/// }
/// ```
abstract contract Assertion is Credible, StateChanges {
    /// @notice The trigger recorder precompile for registering assertion triggers
    /// @dev Address is derived from a deterministic hash for consistency
    TriggerRecorder constant triggerRecorder = TriggerRecorder(address(uint160(uint256(keccak256("TriggerRecorder")))));

    /// @notice The spec recorder precompile for registering the assertion spec
    /// @dev Address is derived from keccak256("cats dining table")
    SpecRecorder constant specRecorder = SpecRecorder(address(uint160(uint256(keccak256("cats dining table")))));

    /// @notice Used to record fn selectors and their triggers.
    function triggers() external view virtual;

    /// @notice Registers a call trigger for the AA without specifying an AA function selector.
    /// This will trigger the assertion function on any call to the AA.
    /// @param fnSelector The function selector of the assertion function.
    function registerCallTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerCallTrigger(fnSelector);
    }

    /// @notice Registers a call trigger for calls to the AA with a specific AA function selector.
    /// @param fnSelector The function selector of the assertion function.
    /// @param triggerSelector The function selector upon which the assertion will be triggered.
    function registerCallTrigger(bytes4 fnSelector, bytes4 triggerSelector) internal view {
        triggerRecorder.registerCallTrigger(fnSelector, triggerSelector);
    }

    /// @notice Registers storage change trigger for any slot
    /// @param fnSelector The function selector of the assertion function.
    function registerStorageChangeTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerStorageChangeTrigger(fnSelector);
    }

    /// @notice Registers storage change trigger for a specific slot
    /// @param fnSelector The function selector of the assertion function.
    /// @param slot The storage slot to trigger on.
    function registerStorageChangeTrigger(bytes4 fnSelector, bytes32 slot) internal view {
        triggerRecorder.registerStorageChangeTrigger(fnSelector, slot);
    }

    /// @notice Registers balance change trigger for the AA
    /// @param fnSelector The function selector of the assertion function.
    function registerBalanceChangeTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerBalanceChangeTrigger(fnSelector);
    }

    /// @notice Registers the desired assertion spec. Must be called within the constructor.
    /// The assertion spec defines what subset of precompiles are available.
    /// Can only be called once. For an assertion to be valid, it needs a defined spec.
    /// @param spec The desired AssertionSpec.
    function registerAssertionSpec(AssertionSpec spec) internal view {
        specRecorder.registerAssertionSpec(spec);
    }
}
