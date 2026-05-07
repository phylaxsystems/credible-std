// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract LiquidationHealthFactorAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    // Simple health factor constants (no scaling)
    uint256 constant LIQUIDATION_THRESHOLD = 100; // Below this = liquidatable
    uint256 constant MIN_HEALTH_FACTOR = 120; // Minimum safe health factor after liquidation

    function triggers() external view override {
        // Register trigger for liquidation function calls
        registerFnCallTrigger(this.assertHealthFactor.selector, ILendingProtocol.liquidate.selector);
    }

    // Check that liquidation can't happen if the position is healthy
    // Check that the health factor is improved after liquidation
    function assertHealthFactor() external {
        // Get the assertion adopter address
        ILendingProtocol adopter = ILendingProtocol(ph.getAssertionAdopter());

        // Get all liquidation calls in the transaction
        PhEvm.CallInputs[] memory callInputs = ph.getAllCallInputs(address(adopter), adopter.liquidate.selector);

        for (uint256 i = 0; i < callInputs.length; i++) {
            address borrower;
            uint256 seizedAssets;
            uint256 repaidDebt;

            // Decode liquidation parameters
            (borrower, seizedAssets, repaidDebt) = abi.decode(callInputs[i].input, (address, uint256, uint256));

            // Validate liquidation amounts
            require(seizedAssets > 0, "Zero assets seized");
            require(repaidDebt > 0, "Zero debt repaid");

            // Check health factor before liquidation
            PhEvm.ForkId memory preCallFork = PhEvm.ForkId({forkType: 2, callIndex: callInputs[i].id});
            uint256 preHealthFactor = adopter.healthFactor(borrower);
            require(preHealthFactor <= LIQUIDATION_THRESHOLD, "Account not eligible for liquidation");

            // Check health factor after liquidation
            PhEvm.ForkId memory postCallFork = PhEvm.ForkId({forkType: 3, callIndex: callInputs[i].id});
            uint256 postHealthFactor = adopter.healthFactor(borrower);

            // Verify the liquidation actually improved the position's health
            require(postHealthFactor > preHealthFactor, "Health factor did not improve after liquidation");

            // Ensure the position is now in a safe state above the minimum required health factor
            require(postHealthFactor >= MIN_HEALTH_FACTOR, "Position still unhealthy after liquidation");
        }
    }
}

// Simplified lending protocol interface
interface ILendingProtocol {
    function liquidate(address borrower, uint256 seizedAssets, uint256 repaidDebt)
        external
        returns (uint256, uint256);

    function isHealthy(address user) external view returns (bool);
    function healthFactor(address user) external view returns (uint256);
}
