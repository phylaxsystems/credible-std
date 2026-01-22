// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestAccessAssertionStorage is Assertion {
    address public someAddress;

    function accessAssertionStorage() external {
        someAddress = address(this);
    }

    function triggers() external view override {
        registerCallTrigger(this.accessAssertionStorage.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
    }
}
