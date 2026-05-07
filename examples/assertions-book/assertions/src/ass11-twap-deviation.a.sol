// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract TwapDeviationAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        // Register trigger for changes to the current price
        // We assume that the price is stored in storage slot 0
        registerTxEndTrigger(this.assertionTwapDeviation.selector);
    }

    // Assert that the current price doesn't deviate more than 5% from the TWAP price
    function assertionTwapDeviation() external {
        // Get the assertion adopter address
        IPool adopter = IPool(ph.getAssertionAdopter());

        // Get TWAP price before the transaction (our reference point)
        PhEvm.ForkId memory preFork = _preTx();
        uint256 preTwapPrice = adopter.twap();

        // Get price after the transaction
        PhEvm.ForkId memory postFork = _postTx();
        uint256 postPrice = adopter.price();

        uint256 maxDeviation = 5;

        // First check: Compare post-transaction price against pre-transaction TWAP
        uint256 deviation = calculateDeviation(preTwapPrice, postPrice);
        require(deviation <= maxDeviation, "Price deviation from TWAP exceeds maximum allowed");

        // Second check: If the simple check passes, inspect all price changes in the callstack
        // This is more expensive but catches manipulation attempts within the transaction
        uint256[] memory priceChanges = getStateChangesUint(
            address(adopter),
            bytes32(uint256(0)) // Current price storage slot
        );

        // Check each price change against the pre-transaction TWAP
        for (uint256 i = 0; i < priceChanges.length; i++) {
            deviation = calculateDeviation(preTwapPrice, priceChanges[i]);
            require(deviation <= maxDeviation, "Price deviation from TWAP exceeds maximum allowed");
        }
    }

    // Helper function to calculate percentage deviation
    function calculateDeviation(uint256 referencePrice, uint256 currentPrice) internal pure returns (uint256) {
        return (((currentPrice > referencePrice) ? currentPrice - referencePrice : referencePrice - currentPrice) * 100)
            / referencePrice;
    }
}

interface IPool {
    function price() external view returns (uint256);
    function twap() external view returns (uint256);
}
