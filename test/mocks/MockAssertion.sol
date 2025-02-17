// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../src/Assertion.sol";
import {MockPhEvm} from "./MockPhEvm.sol";
import {PhEvm} from "../../src/PhEvm.sol";

contract MockAssertion is Assertion {
    constructor() {
        ph = PhEvm(new MockPhEvm());
    }

    function triggers() external view override {
        registerCallTrigger(this.assertionTrue.selector);
    }

    function assertionTrue() public pure returns (bool) {
        return true;
    }
}
