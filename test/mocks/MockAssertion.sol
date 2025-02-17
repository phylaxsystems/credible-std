// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../src/Assertion.sol";

contract MockAssertion is Assertion {
    function triggers() external view override {
        registerCallTrigger(this.assertionTrue.selector);
    }

    function assertionTrue() public pure returns (bool) {
        return true;
    }
}
