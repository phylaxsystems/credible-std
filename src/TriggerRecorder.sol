// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface TriggerRecorder {
    /// @notice Records a call trigger for the specified assertion function.
    /// A call trigger signifies that the assertion function should be called
    /// if the assertion adopter is called.
    /// @param fnSelector The function selector of the assertion function.
    function registerCallTrigger(bytes4 fnSelector) external view;
}
