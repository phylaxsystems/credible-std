// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";

import {Target, TARGET} from "../common/Target.sol";

contract TestForking is Assertion, Test {
    uint256 expectedSum = 0;
    uint256 someInitValue = 1;
    address newTarget = address(0x1A9c28714584DC5Bc4715C0624c171B5F4F82Be8);

    constructor() payable {}

    function testForkSwitch() external {
        uint256 calls = ph
            .getCallInputs(address(TARGET), TARGET.incrementStorage.selector)
            .length;

        uint256 startValue = TARGET.readStorage();
        require(startValue < 3, "startValue >= 3");

        //Test fork switching reads from underlying state
        require(
            TARGET.readStorage() == startValue + calls,
            "readStorage() != startValue + calls"
        );

        ph.forkPreState();
        require(
            TARGET.readStorage() == startValue,
            "readStorage() != startValue"
        );
        require(newTarget.code.length == 0, "preState newTarget.code.length != 0");

        ph.forkPostState();
        require(
            TARGET.readStorage() == startValue + calls,
            "readStorage() != startValue + calls"
        );
        require(newTarget.code.length != 0, "postState newTarget.code.length == 0");

        ph.forkPreState();
        require(
            TARGET.readStorage() == startValue,
            "readStorage() != startValue"
        );
    }

    function testPersistTargetContracts() external {
        require(someInitValue == 1, "someInitValue != 1");
        uint256 sum = 0;

        require(TARGET.readStorage() == 2, "val != 2");
        expectedSum += TARGET.readStorage();
        sum += TARGET.readStorage();

        ph.forkPreState();
        require(TARGET.readStorage() == 1, "readStorage != 1");
        expectedSum += TARGET.readStorage();
        sum += TARGET.readStorage();

        ph.forkPostState();
        require(TARGET.readStorage() == 2, "val != 2");
        expectedSum += TARGET.readStorage();
        sum += TARGET.readStorage();

        ph.forkPreState();
        require(TARGET.readStorage() == 1, "val != 1");
        expectedSum += TARGET.readStorage();
        sum += TARGET.readStorage();

        require(sum == expectedSum, "sum != expectedSum");
        require(sum == 6, "sum != 6");
    }

    function triggers() external view override {
        registerCallTrigger(this.testForkSwitch.selector);
        registerCallTrigger(this.testPersistTargetContracts.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
        // Test code before and after
        new Target();
    }
}
