// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";

import {Target, TARGET} from "../common/Target.sol";

contract TestLoad is Assertion {
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

    function loadRandomAccount() external view {
        require(ph.load(address(0x00000000000000000000000000000000001bd5a0), 0) == 0, "load(randomAccount) != 0");
    }

    function triggers() external view override {
        registerCallTrigger(this.load.selector);
        registerCallTrigger(this.loadRandomAccount.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
    }
}
