// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../Assertion.sol";
import {PhEvm} from "../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Target, TARGET} from "../common/Target.sol";

contract ShouldFail {
    function test() external view {
        revert();
    }

    function triggers() external view override {
        registerCallTrigger(this.test.selector);
    }
}

contract ShouldSucceed {
    function test() external view {}

    function triggers() external view override {
        registerCallTrigger(this.test.selector);
    }
}
