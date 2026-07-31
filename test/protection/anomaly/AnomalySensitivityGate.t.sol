// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Sensitivity} from "credible-std/Sensitivity.sol";
import {AnomalyCompositeAssertion} from "credible-std/protection/anomaly/AnomalyCompositeAssertion.sol";
import {AnomalyGatedBaseAssertion} from "credible-std/protection/anomaly/AnomalyGatedBaseAssertion.sol";
import {CompositeTxEndHarness} from "./AnomalyCompositeAssertion.t.sol";
import {MockERC20, Vault} from "./AnomalyTestMocks.sol";

// The `Sensitivity` ladder and the constructor guard standing on it. The level *comparison* is not
// here: the trigger performs it, against the target's own model, so it lives in the executor and is
// tested there. What credible-std owns is the ladder's shape and the refusal to deploy an assertion
// naming a level that is not on it.

contract TestAnomalySensitivity is Test {
    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
    }

    function _config(uint8 level) internal view returns (AnomalyCompositeAssertion.Config memory c) {
        c.target = address(vault);
        c.sensitivity = level;
        c.useDrain = true;
        c.outflowTarget = address(vault);
        c.outflowToken = address(token);
        c.outflowFracBps = 250;
    }

    /// The ladder's bounds and its recommended rung, pinned so a change to the product decision has
    /// to be made in `Sensitivity` rather than drifting in.
    function test_ladder_bounds_and_recommended_level() public pure {
        assertEq(Sensitivity.MIN, 1);
        assertEq(Sensitivity.MAX, 10);
        assertEq(Sensitivity.RECOMMENDED, Sensitivity.LEVEL_7);
        assertEq(Sensitivity.LEVEL_1, 1);
        assertEq(Sensitivity.LEVEL_10, 10);
    }

    /// `0` is the "cleared nothing" sentinel an unscored target reads back, not a level. Treating
    /// it as one would gate true on every contract the model never scored.
    function test_zero_is_not_a_level() public pure {
        assertFalse(Sensitivity.isValid(0));
        assertFalse(Sensitivity.isValid(11));
        assertFalse(Sensitivity.isValid(type(uint8).max));
        for (uint8 level = Sensitivity.MIN; level <= Sensitivity.MAX; level++) {
            assertTrue(Sensitivity.isValid(level));
        }
    }

    /// Every rung deploys, and nothing off the ladder does. An assertion naming a level the trigger
    /// cannot register would ship protecting nothing.
    function test_every_rung_deploys_and_nothing_else_does() public {
        for (uint8 level = Sensitivity.MIN; level <= Sensitivity.MAX; level++) {
            new CompositeTxEndHarness(_config(level));
        }

        vm.expectRevert(AnomalyGatedBaseAssertion.SensitivityOutOfRange.selector);
        new CompositeTxEndHarness(_config(0));

        vm.expectRevert(AnomalyGatedBaseAssertion.SensitivityOutOfRange.selector);
        new CompositeTxEndHarness(_config(Sensitivity.MAX + 1));
    }
}
