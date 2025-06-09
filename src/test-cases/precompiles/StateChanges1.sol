// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestStateChanges1 is Assertion, Test {
    constructor() payable {}

    function testGetStateChanges1() external view {
        bytes32[] memory changes = ph.getStateChanges(
            address(TARGET),
            bytes32(0)
        );

        require(changes.length == 2, "changes.length != 2");

        require(uint256(changes[0]) == 1, "changes[0] != 1");
        require(uint256(changes[1]) == 5, "changes[1] != 5");
    }

    function triggers() external view override {
        registerCallTrigger(this.testGetStateChanges1.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(5);

        // Test that state changes before reverts are not included.
        try TARGET.writeStorageAndRevert(10) {
            revert("Expected revert");
        } catch Error(string memory) {
            console.log("Caught revert as expected");
        }
    }
}
