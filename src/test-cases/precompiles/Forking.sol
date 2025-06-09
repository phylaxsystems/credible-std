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
    uint256 expectedDiff;
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
        uint256 _expectedDiff = initData.expectedDiff;

        require(someInitValue == 1, "someInitValue != 1");
        require(sum == 0, "expectedSum != 0");

        uint256 expectedPreValue = _startValue;
        uint256 expectedPostValue = _startValue + _expectedDiff;

        require(
            TARGET.readStorage() == expectedPostValue,
            "val != expectedPostValue"
        );
        sum += TARGET.readStorage();
        require(sum == expectedPostValue, "sum != expectedPostValue");

        ph.forkPreState();
        require(
            TARGET.readStorage() == expectedPreValue,
            "readStorage != expectedPreValue"
        );

        sum += TARGET.readStorage();
        require(
            sum == expectedPreValue + expectedPostValue,
            "sum != expectedPreValue + expectedPostValue"
        );

        ph.forkPostState();
        require(
            TARGET.readStorage() == expectedPostValue,
            "val != expectedPostValue"
        );
        sum += TARGET.readStorage();
        require(
            sum == expectedPreValue + (expectedPostValue * 2),
            "sum != expectedPreValue + (expectedPostValue * 2)"
        );

        ph.forkPreState();
        require(
            TARGET.readStorage() == expectedPreValue,
            "readStorage != expectedPreValue"
        );
        sum += TARGET.readStorage();
        require(
            sum == (expectedPreValue + expectedPostValue) * 2,
            "sum != (expectedPreValue + expectedPostValue) * 2"
        );
        require(sum == _expectedSum, "sum != _expectedSum");
    }

    function triggers() external view override {
        registerCallTrigger(this.testForkSwitchStorage.selector);
        registerCallTrigger(this.testForkSwitchNewDeployedContract.selector);
        registerCallTrigger(this.testPersistTargetContracts.selector);
    }
}

contract TestForkingTx0 is ForkingTest {
    constructor()
        ForkingTest(
            InitData({
                newTarget: address(0x40f7EBE92dD6bdbEECADFFF3F9d7A1B33Cf8d7c0),
                startValue: 1,
                expectedSumPersistence: 4,
                expectedDiff: 1
            })
        )
    {}
}

contract TestForkingTx1 is ForkingTest {
    constructor()
        ForkingTest(
            InitData({
                newTarget: address(0x8019401e3Eda99Ff0f7fee39e6Ae724006390A61),
                startValue: 2,
                expectedSumPersistence: 10,
                expectedDiff: 1
            })
        )
    {}
}

contract TestForkingTxMb is ForkingTest {
    constructor()
        ForkingTest(
            InitData({
                newTarget: address(0x40f7EBE92dD6bdbEECADFFF3F9d7A1B33Cf8d7c0),
                startValue: 1,
                expectedSumPersistence: 8,
                expectedDiff: 2
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
