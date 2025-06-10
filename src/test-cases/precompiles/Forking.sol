// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";

import {Target, TARGET} from "../common/Target.sol";


contract TestForking is Assertion, Test {
    uint256 public sum = 0;
    uint256 public someInitValue = 1;

    function testForkSwitchStorage() external {
        //Test fork switching reads from underlying state
        require(TARGET.readStorage() == 2, "postStateValue != 2 (no switch)");
        ph.forkPreState();
        uint256 preStateValue = TARGET.readStorage();
        require(preStateValue == 1, "preStateValue != 1");

        ph.forkPostState();
        //Test fork switching reads from underlying state
        require(TARGET.readStorage() == 2, "postStateValue != 2 (switch)");
    }

    function testForkSwitchNewDeployedContract() external {
        address newTarget = address(0x40f7EBE92dD6bdbEECADFFF3F9d7A1B33Cf8d7c0);

        require(
            newTarget.code.length != 0,
            "post state newTarget.code.length should not be 0"
        );

        ph.forkPreState();
        require(
            newTarget.code.length == 0,
            "pre state newTarget.code.length should be 0"
        );

        ph.forkPostState();
        require(
            newTarget.code.length != 0,
            "post state newTarget.code.length should not be 0"
        );
    }
    function testForkSwitchBalance() external {
        require(address(TARGET).balance == 1000, "balance != 1000");
        ph.forkPreState();
        require(address(TARGET).balance == 0, "balance != 0");
        ph.forkPostState();
        require(address(TARGET).balance == 1000, "balance != 1000");
    }

    function testPersistTargetContracts() external {
        require(someInitValue == 1, "someInitValue != 1");
        require(sum == 0, "expectedSum != 0");

        require(TARGET.readStorage() == 2, "postStateValue != 2 (no switch)");
        sum += TARGET.readStorage();

        ph.forkPreState();
        require(TARGET.readStorage() == 1, "preStateValue != 1");

        sum += TARGET.readStorage();

        ph.forkPostState();
        require(TARGET.readStorage() == 2, "postStateValue != 2 (switch)");
        sum += TARGET.readStorage();

        ph.forkPreState();
        require(TARGET.readStorage() == 1, "preStateValue != 1");
        sum += TARGET.readStorage();

        require(sum == 6, "sum != 6");
    }

    function triggers() external view override {
        registerCallTrigger(this.testForkSwitchStorage.selector);
        registerCallTrigger(this.testForkSwitchNewDeployedContract.selector);
        registerCallTrigger(this.testPersistTargetContracts.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
        (bool success, ) = address(TARGET).call{value: 1000}("");
        require(success, "call failed");
    }
}
