// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestStorageSlotChangeTrigger is Assertion {
    function triggered() external pure {
        revert();
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.triggered.selector, 0);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(2);
    }
}
