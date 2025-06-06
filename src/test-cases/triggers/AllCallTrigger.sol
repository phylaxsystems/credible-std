// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Target, TARGET} from "../common/Target.sol";

contract AllCallTrigger is Assertion {
    function testTriggered() external pure {
        revert();
    }

    function triggers() external view override {
        registerCallTrigger(this.testTriggered.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
    }
}
