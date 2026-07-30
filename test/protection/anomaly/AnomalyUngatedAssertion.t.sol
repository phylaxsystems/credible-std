// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Sensitivity} from "credible-std/Sensitivity.sol";
import {AnomalyGatedBaseAssertion} from "credible-std/protection/anomaly/AnomalyGatedBaseAssertion.sol";
import {AnomalyUngatedAssertion} from "credible-std/protection/anomaly/AnomalyUngatedAssertion.sol";
import {MockERC20, Vault} from "./AnomalyTestMocks.sol";

// The firing decision belongs to the executor, which resolves the level against the target's own
// model. What credible-std owns is the ladder guard and the unconditional revert.

contract UngatedHarness is AnomalyUngatedAssertion {
    constructor(address target_, uint8 sensitivity_) AnomalyGatedBaseAssertion(target_, sensitivity_) {}

    function triggers() external view override {
        _registerUngatedTrigger();
    }
}

contract TestAnomalyUngatedAssertion is Test {
    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
    }

    /// One invalidation per firing, with nothing left to decide in the body.
    function test_body_reverts_unconditionally() public {
        UngatedHarness bare = new UngatedHarness(address(vault), Sensitivity.RECOMMENDED);

        vm.expectRevert();
        bare.assertNotAnomalous();
    }

    /// A level off the ladder would be permanently inert, so it is refused at deploy.
    function test_rejects_a_level_off_the_ladder() public {
        vm.expectRevert(AnomalyGatedBaseAssertion.SensitivityOutOfRange.selector);
        new UngatedHarness(address(vault), Sensitivity.MAX + 1);

        vm.expectRevert(AnomalyGatedBaseAssertion.SensitivityOutOfRange.selector);
        new UngatedHarness(address(vault), 0);

        vm.expectRevert(AnomalyGatedBaseAssertion.ZeroTarget.selector);
        new UngatedHarness(address(0), Sensitivity.RECOMMENDED);
    }

    /// Every rung deploys.
    function test_every_rung_deploys() public {
        for (uint8 level = Sensitivity.MIN; level <= Sensitivity.MAX; level++) {
            UngatedHarness bare = new UngatedHarness(address(vault), level);
            assertTrue(address(bare) != address(0));
        }
    }
}
