// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract OracleLivenessAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    // Maximum time window (in seconds) that oracle data can be considered fresh
    // This is a constant that should be adjusted based on the protocol's requirements
    uint256 public constant MAX_UPDATE_WINDOW = 10 minutes;

    function triggers() external view override {
        // Register trigger for the swap function which relies on oracle data
        registerFnCallTrigger(this.assertionOracleLiveness.selector, IDex.swap.selector);
    }

    // Assert that the oracle has been updated within the specified time window
    function assertionOracleLiveness() external {
        // Get the assertion adopter address
        IDex adopter = IDex(ph.getAssertionAdopter());

        // Get the current state to check the oracle's last update time
        PhEvm.ForkId memory postFork = _postTx();

        // Check if the oracle has been updated within the maximum allowed window
        uint256 lastUpdateTime = IOracle(adopter.oracle()).lastUpdated();
        uint256 currentTime = block.timestamp;

        // Verify the oracle data is fresh (updated within the time window)
        require(currentTime - lastUpdateTime <= MAX_UPDATE_WINDOW, "Oracle not updated within the allowed time window");
    }
}

interface IOracle {
    function lastUpdated() external view returns (uint256);
}

interface IDex {
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256);
    function oracle() external view returns (IOracle);
}
