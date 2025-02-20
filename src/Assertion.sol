// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";
import {TriggerRecorder} from "./TriggerRecorder.sol";
import {StateChanges} from "./StateChanges.sol";

/// @notice Assertion interface for the PhEvm precompile
abstract contract Assertion is Credible, StateChanges {
    //Trigger recorder address
    TriggerRecorder constant triggerRecorder = TriggerRecorder(address(uint160(uint256(keccak256("TriggerRecorder")))));

    /// @notice Used to record fn selectors and their triggers.
    function triggers() external view virtual;

    /// @notice Registers a call trigger for the specified assertion function.
    function registerCallTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerCallTrigger(fnSelector);
    }
}
