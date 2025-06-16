// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestBalanceTrigger is Assertion {
    function triggered() external pure {
        revert();
    }

    function triggers() external view override {
        registerBalanceChangeTrigger(this.triggered.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        (bool success,) = address(TARGET).call{value: 1}("");
        require(success, "Failed to send ETH");
    }
}
