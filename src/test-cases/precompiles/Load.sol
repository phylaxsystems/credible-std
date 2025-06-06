// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestLoad is Assertion, Test {
    constructor() payable {}

    function testLoad() external {
        ph.forkPreState();

        uint256 preCount = uint256(ph.load(address(TARGET), 0));

        ph.forkPostState();

        uint256 postCount = uint256(ph.load(address(TARGET), 0));

        uint256 callCount = ph
            .getCallInputs(address(TARGET), Target.incrementStorage.selector)
            .length;

        require(postCount - preCount == callCount, "Values not as expected");
    }

    function triggers() external view override {
        registerCallTrigger(this.testLoad.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
    }
}
