// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
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
    /// The precompile's address, from `Credible`. Nothing is deployed there under `forge`, so the
    /// context read has to be mocked or it reverts on decoding empty return data.
    address internal constant PH = address(uint160(uint256(keccak256("Kim Jong Un Sucks"))));

    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
    }

    /// Answer `anomalyContext(target)` with `firesAt`, so the body reaches its own revert instead of
    /// failing on the absent precompile.
    function _mockFiresAt(address target, uint8 firesAt) internal {
        vm.mockCall(
            PH,
            abi.encodeWithSelector(PhEvm.anomalyContext.selector, target),
            abi.encode(PhEvm.AnomalyContext({firesAt: firesAt}))
        );
    }

    /// One invalidation per firing, with nothing left to decide in the body.
    ///
    /// Asserted on the encoded custom error rather than any revert: the body reads the anomaly
    /// context before it reverts, so a bare `expectRevert` also passes when that read is what
    /// failed, which proves nothing about this assertion.
    function test_body_reverts_with_the_anomalous_transaction_error() public {
        UngatedHarness bare = new UngatedHarness(address(vault), Sensitivity.RECOMMENDED);
        _mockFiresAt(address(vault), Sensitivity.RECOMMENDED);

        vm.expectRevert(
            abi.encodeWithSelector(AnomalyUngatedAssertion.AnomalousTransaction.selector, Sensitivity.RECOMMENDED)
        );
        bare.assertNotAnomalous();
    }

    /// The error carries the context's own `firesAt`, so an operator reading an invalidation learns
    /// the rung the transaction cleared rather than the rung the assertion was registered at.
    function test_error_carries_the_contexts_fires_at() public {
        UngatedHarness bare = new UngatedHarness(address(vault), Sensitivity.RECOMMENDED);

        for (uint8 firesAt = Sensitivity.MIN; firesAt <= Sensitivity.MAX; firesAt++) {
            _mockFiresAt(address(vault), firesAt);
            vm.expectRevert(abi.encodeWithSelector(AnomalyUngatedAssertion.AnomalousTransaction.selector, firesAt));
            bare.assertNotAnomalous();
        }
    }

    /// The body is ungated, so it reverts on a context that cleared nothing too. The trigger is what
    /// decides whether it runs at all, and the executor never dispatches on `firesAt == 0`.
    function test_body_reverts_even_when_the_context_cleared_no_level() public {
        UngatedHarness bare = new UngatedHarness(address(vault), Sensitivity.RECOMMENDED);
        _mockFiresAt(address(vault), 0);

        vm.expectRevert(abi.encodeWithSelector(AnomalyUngatedAssertion.AnomalousTransaction.selector, uint8(0)));
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
