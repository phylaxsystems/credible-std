// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";

/// @notice Assertion interface for the PhEvm precompile
abstract contract Assertion is Credible {
    /// @notice The type of state change that triggers the assertion
    enum TriggerType {
        /// @notice The assertion is triggered by a storage change
        STORAGE,
        /// @notice The assertion is triggered by a transfer of ether
        ETHER,
        /// @notice The assertion is triggered by both a storage change and a transfer of ether
        BOTH
    }

    /// @notice A struct that contains the type of state change and the function selector of the assertion function
    struct Trigger {
        /// @notice The type of state change that triggers the assertion
        TriggerType triggerType;
        /// @notice The assertion function selector
        bytes4 fnSelector;
    }

    /// @notice Returns all the triggers for the assertion
    /// @return An array of Trigger structs
    function fnSelectors() external pure virtual returns (Trigger[] memory);
}
