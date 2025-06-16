// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestSomeCallTrigger is Assertion {
    function triggered() external pure {
        revert();
    }

    function triggers() external view override {
        registerCallTrigger(this.triggered.selector, Target.incrementStorage.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
    }
}
