// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract PriceWithinTicksAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    // Uniswap V3 tick bounds
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;

    function triggers() external view override {
        // Register trigger for changes to the tick storage slot
        // Assumes tick is stored in slot0 of the pool contract
        registerTxEndTrigger(this.priceWithinTicks.selector);
    }

    // Check that the price is within the tick bounds and that the tick is divisible by the tick spacing
    function priceWithinTicks() external {
        // Get the assertion adopter address
        IUniswapV3Pool adopter = IUniswapV3Pool(ph.getAssertionAdopter());

        // Get post-swap state
        PhEvm.ForkId memory postFork = _postTx();
        (, int24 postTick,,,,,) = adopter.slot0();
        int24 spacing = adopter.tickSpacing();

        // Check 1: Tick must be within global bounds
        require(postTick >= MIN_TICK && postTick <= MAX_TICK, "Tick outside global bounds");

        // Check 2: Tick must be divisible by tickSpacing
        require(postTick % spacing == 0, "Tick not aligned with spacing");
    }
}

// Uniswap v3 pool style interface
interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function tickSpacing() external view returns (int24);
}
