// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Target, TARGET} from "../common/Target.sol";

contract AllStorageChangeTrigger is Assertion {
    function testTriggered() external {
        ph.forkPreState();
        if (address(TARGET).code.length != 0) {
            revert("Target not deployed yet");
        }
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.testTriggered.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(2);
    }
}
