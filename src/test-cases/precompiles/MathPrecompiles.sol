// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestMathPrecompiles is Assertion {
    constructor() payable {}

    function mulDivDownRoundsTowardZero() external view {
        require(ph.mulDivDown(7, 3, 2) == 10, "7*3/2 floor != 10");
        require(ph.mulDivDown(6, 3, 2) == 9, "6*3/2 floor != 9");
        require(ph.mulDivDown(0, 1234, 5) == 0, "0*x/y != 0");
        require(ph.mulDivDown(1, 1, 2) == 0, "1*1/2 floor != 0");
    }

    function mulDivUpRoundsAwayFromZero() external view {
        require(ph.mulDivUp(7, 3, 2) == 11, "7*3/2 ceil != 11");
        require(ph.mulDivUp(6, 3, 2) == 9, "6*3/2 ceil != 9 (exact)");
        require(ph.mulDivUp(1, 1, 2) == 1, "1*1/2 ceil != 1");
        require(ph.mulDivUp(0, 1234, 5) == 0, "ceil(0) != 0");
    }

    function mulDivHandlesWideIntermediates() external view {
        // Without 512-bit intermediates, max * 2 would overflow.
        uint256 max = type(uint256).max;
        require(ph.mulDivDown(max, 2, max) == 2, "mulDivDown(max,2,max) != 2");
        require(ph.mulDivUp(max, 2, max) == 2, "mulDivUp(max,2,max) != 2");
    }

    function normalizeDecimalsUpscalesAndDownscales() external view {
        require(ph.normalizeDecimals(1e6, 6, 18) == 1e18, "1e6@6 -> 18 != 1e18");
        require(ph.normalizeDecimals(1e18, 18, 6) == 1e6, "1e18@18 -> 6 != 1e6");
        require(ph.normalizeDecimals(123, 8, 8) == 123, "no-op decimals changed value");
        require(ph.normalizeDecimals(0, 6, 18) == 0, "0 should stay 0");
    }

    function ratioGePassesExactEquality() external view {
        // 10/2 == 5/1 — equal ratios, zero tolerance.
        require(ph.ratioGe(10, 2, 5, 1, 0), "10/2 >= 5/1 should hold");
    }

    function ratioGeFailsWhenStrictlySmaller() external view {
        // 4/2 < 5/2, zero tolerance.
        require(!ph.ratioGe(4, 2, 5, 2, 0), "4/2 should not be >= 5/2");
    }

    function ratioGeRespectsTolerance() external view {
        // 19/1 vs 20/1 with 1000 bps tolerance: 19 >= 20 * (1 - 0.10) = 18 -> true
        require(ph.ratioGe(19, 1, 20, 1, 1000), "19 should clear 20 within 10% tolerance");

        // 17/1 vs 20/1 with 1000 bps: 17 < 18 -> false
        require(!ph.ratioGe(17, 1, 20, 1, 1000), "17 should fail 20 within 10% tolerance");
    }

    function triggers() external view override {
        registerCallTrigger(this.mulDivDownRoundsTowardZero.selector);
        registerCallTrigger(this.mulDivUpRoundsAwayFromZero.selector);
        registerCallTrigger(this.mulDivHandlesWideIntermediates.selector);
        registerCallTrigger(this.normalizeDecimalsUpscalesAndDownscales.selector);
        registerCallTrigger(this.ratioGePassesExactEquality.selector);
        registerCallTrigger(this.ratioGeFailsWhenStrictlySmaller.selector);
        registerCallTrigger(this.ratioGeRespectsTolerance.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
    }
}
