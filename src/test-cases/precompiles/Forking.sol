// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Test} from "forge-std/Test.sol";

import {Target, TARGET} from "../common/Target.sol";
struct InitData {
    address newTarget;
    uint256 startValue;
    uint256 expectedSumPersistence;
}

abstract contract ForkingTest is Assertion, Test {
    uint256 public sum = 0;
    uint256 public someInitValue = 1;

    InitData public initData;

    constructor(InitData memory _initData) payable {
        initData = _initData;
    }

    function testForkSwitchStorage() external {
        uint256 startValue = initData.startValue;

        //Test fork switching reads from underlying state
        require(
            TARGET.readStorage() == startValue + 1,
            "readStorage() != startValue + 1"
        );
        ph.forkPreState();
        uint256 preStateValue = TARGET.readStorage();
        require(preStateValue == startValue, "preStateValue != startValue");

        ph.forkPostState();
        //Test fork switching reads from underlying state
        require(
            TARGET.readStorage() == startValue + 1,
            "readStorage() != startValue + 1"
        );
    }

    function testForkSwitchNewDeployedContract() external {
        address newTarget = initData.newTarget;

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

    function testPersistTargetContracts() external {
        uint256 _startValue = initData.startValue;
        uint256 _expectedSum = initData.expectedSumPersistence;

        require(someInitValue == 1, "someInitValue != 1");
        require(sum == 0, "expectedSum != 0");

        require(
            TARGET.readStorage() == _startValue + 1,
            "val != _startValue + 1"
        );
        sum += TARGET.readStorage();
        require(sum == _startValue + 1, "sum != _startValue + 1");

        ph.forkPreState();
        require(
            TARGET.readStorage() == _startValue,
            "readStorage != _startValue"
        );
        sum += TARGET.readStorage();
        require(sum == (_startValue * 2 + 1), "sum != _startValue * 2 + 1");

        ph.forkPostState();
        require(
            TARGET.readStorage() == _startValue + 1,
            "val != _startValue + 1"
        );
        sum += TARGET.readStorage();
        require(sum == ((_startValue * 3) + 2), "sum != _startValue * 2 + 2");

        ph.forkPreState();
        require(
            TARGET.readStorage() == _startValue,
            "readStorage != _startValue"
        );
        sum += TARGET.readStorage();
        require(sum == ((_startValue * 4) + 2), "sum != _startValue * 4 + 2");
        require(sum == _expectedSum, "sum != _expectedSum");
    }

    function triggers() external view override {
        registerCallTrigger(this.testForkSwitchStorage.selector);
        registerCallTrigger(this.testForkSwitchNewDeployedContract.selector);
        registerCallTrigger(this.testPersistTargetContracts.selector);
    }
}

contract TestForking0 is ForkingTest {
    constructor()
        ForkingTest(
            InitData({
                newTarget: address(0x1A9c28714584DC5Bc4715C0624c171B5F4F82Be8),
                startValue: 1,
                expectedSumPersistence: 6
            })
        )
    {}
}

contract TestForking1 is ForkingTest {
    constructor()
        ForkingTest(
            InitData({
                newTarget: address(0x1A9c28714584DC5Bc4715C0624c171B5F4F82Be8),
                startValue: 2,
                expectedSumPersistence: 10
            })
        )
    {}
}

contract TriggeringTx {
    constructor() payable {
        TARGET.incrementStorage();
        // Test code before and after
        new Target();
    }
}
