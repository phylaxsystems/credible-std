// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";

import {Target, TARGET} from "../common/Target.sol";

contract TestGetAdopter is Assertion {
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
