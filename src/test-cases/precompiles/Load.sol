// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestLoad is Assertion, Test {
    constructor() payable {}

    function _loadCount() internal view returns (uint256) {
        return uint256(ph.load(address(TARGET), 0));
    }

    function load() external {
        require(_loadCount() == 2, "postStateCount != 2 (no switch)");
        require(TARGET.readStorage() == _loadCount(), "readStorage != postStateCount (no switch)");

        ph.forkPreState();
        require(_loadCount() == 1, "preStateCount != 1");
        require(TARGET.readStorage() == _loadCount(), "readStorage != preStateCount");

        ph.forkPostState();
        require(_loadCount() == 2, "postStateCount != 2 (switch)");
        require(TARGET.readStorage() == _loadCount(), "readStorage != postStateCount (switch)");
    }

    function triggers() external view override {
        registerCallTrigger(this.load.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
    }
}
