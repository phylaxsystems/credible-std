// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";
import {console} from "forge-std/console.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestStateChangesNone is Assertion {
    constructor() payable {}

    function getStateChangesNone() external view {
        bytes32[] memory changes = ph.getStateChanges(address(TARGET), bytes32(0));
        require(changes.length == 0, "changes.length != 0");
    }

    function triggers() external view override {
        registerCallTrigger(this.getStateChangesNone.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        // Test that state changes before reverts are not included.
        try TARGET.writeStorageAndRevert(10) {
            revert("Expected revert");
        } catch Error(string memory) {
            console.log("Caught revert as expected");
        }

        (bool success,) = address(TARGET).call("");
        require(success, "call failed");
    }
}
