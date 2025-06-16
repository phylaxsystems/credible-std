// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestAllStorageChangeTrigger is Assertion {
    function triggered() external {
        ph.forkPreState();
        if (address(TARGET).code.length != 0) {
            if (TARGET.readStorage() != 0) {
                revert(
                    "Initial storage not 0, contract deployed before this transaction, assertion triggered as expected"
                );
            } else {
                //Initial storage 0, contract not deployed before this transaction.
            }
        }
    }

    function triggers() external view override {
        registerStorageChangeTrigger(this.triggered.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(2);
    }
}
