// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestGetAdopter is Assertion, Test {
    constructor() payable {}

    function getAdopter() external view {
        address adopter = ph.getAssertionAdopter();
        require(adopter == address(TARGET), "adopter != target");
    }

    function triggers() external view override {
        registerCallTrigger(this.getAdopter.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
    }
}
