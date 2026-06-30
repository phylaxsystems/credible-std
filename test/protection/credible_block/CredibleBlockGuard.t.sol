// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {ICredibleRegistry} from "../../../src/protection/credible_block/ICredibleRegistry.sol";
import {CredibleBlockGuard} from "../../../src/protection/credible_block/CredibleBlockGuard.sol";

/// @notice Test double for the Credible Registry. Exposes fine-grained setters and a faithful
///         `markCurrentBlockCredible()` replicating `phylaxsystems/credible-registry` semantics.
contract MockCredibleRegistry is ICredibleRegistry {
    mapping(uint256 blockNumber => bool credible) internal _credible;
    uint256 internal _lastCredibleBlock;

    function setCredibleBlock(uint256 blockNumber, bool credible) external {
        _credible[blockNumber] = credible;
    }

    function setLastCredibleBlock(uint256 blockNumber) external {
        _lastCredibleBlock = blockNumber;
    }

    /// @dev Mirrors the real registry: marks `block.number` credible and advances the pointer.
    function markCurrentBlockCredible() external {
        _credible[block.number] = true;
        _lastCredibleBlock = block.number;
    }

    function isCredibleBlock(uint256 blockNumber) external view returns (bool) {
        return _credible[blockNumber];
    }

    function lastCredibleBlock() external view returns (uint256) {
        return _lastCredibleBlock;
    }
}

/// @notice Minimal protocol contract that adopts the guard and protects a function with the
///         {CredibleBlockGuard.onlyCredibleBlock} modifier, exactly how an integrator would.
contract GuardedVault is CredibleBlockGuard {
    uint256 public actions;

    constructor(ICredibleRegistry registry_, uint256 threshold_) CredibleBlockGuard(registry_, threshold_) {}

    /// @dev Gated: only executes in a credible block (or while failing open).
    function doProtectedAction() external onlyCredibleBlock {
        actions++;
    }

    /// @dev Ungated control: must always execute regardless of credibility.
    function doUnguardedAction() external returns (uint256) {
        return ++actions;
    }
}

contract CredibleBlockGuardTest is Test {
    /// @dev ~15 minutes of 12s blocks; chosen so boundaries are easy to reason about.
    uint256 internal constant THRESHOLD = 75;
    uint256 internal constant BASE_BLOCK = 1_000_000;

    MockCredibleRegistry internal registry;
    GuardedVault internal vault;

    function setUp() public {
        registry = new MockCredibleRegistry();
        vault = new GuardedVault(registry, THRESHOLD);
        vm.roll(BASE_BLOCK);
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function test_constructor_storesArgs() public view {
        assertEq(address(vault.credibleRegistry()), address(registry));
        assertEq(vault.failOpenBlockThreshold(), THRESHOLD);
    }

    function test_constructor_revertsOnZeroRegistry() public {
        vm.expectRevert(CredibleBlockGuard.ZeroCredibleRegistryAddress.selector);
        new GuardedVault(ICredibleRegistry(address(0)), THRESHOLD);
    }

    function test_constructor_revertsOnZeroThreshold() public {
        vm.expectRevert(CredibleBlockGuard.ZeroFailOpenBlockThreshold.selector);
        new GuardedVault(registry, 0);
    }

    // ---------------------------------------------------------------------
    // Allow path: current block is credible
    // ---------------------------------------------------------------------

    function test_allows_whenCurrentBlockCredible() public {
        registry.markCurrentBlockCredible();

        vault.doProtectedAction();
        assertEq(vault.actions(), 1);
        assertTrue(vault.isCurrentBlockAllowed());
        assertFalse(vault.failOpenActive());
    }

    function test_allows_whenCurrentBlockCredible_lastPointerEqualsCurrent() public {
        // lastCredibleBlock == current block -> gap 0, not fail open; credibility carries allow.
        registry.markCurrentBlockCredible();
        assertEq(registry.lastCredibleBlock(), block.number);
        vault.doProtectedAction();
        assertEq(vault.actions(), 1);
    }

    // ---------------------------------------------------------------------
    // Modifier scope: only the guarded function is gated
    // ---------------------------------------------------------------------

    function test_unguardedFunction_runsInNonCredibleBlock() public {
        // Builder live, block not credible -> guarded path would revert, unguarded must not.
        registry.setLastCredibleBlock(block.number - 1);
        assertEq(vault.doUnguardedAction(), 1);
    }

    // ---------------------------------------------------------------------
    // Block path: builder set live, current block not credible
    // ---------------------------------------------------------------------

    function test_reverts_whenNotCredible_withinThreshold() public {
        // Last credible block is 10 behind (<= 75) -> builder set still considered live.
        registry.setLastCredibleBlock(block.number - 10);

        assertFalse(vault.isCurrentBlockAllowed());
        vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
        vault.doProtectedAction();
        assertEq(vault.actions(), 0);
    }

    function test_reverts_atFailOpenBoundary() public {
        // gap == threshold (75) is NOT strictly greater -> still live -> must be credible.
        registry.setLastCredibleBlock(block.number - THRESHOLD);

        vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
        vault.doProtectedAction();
    }

    // ---------------------------------------------------------------------
    // Fail-open path: builder set offline
    // ---------------------------------------------------------------------

    function test_failsOpen_whenGapExceedsThreshold() public {
        // gap == threshold + 1 (76) -> fail open even though current block is not credible.
        registry.setLastCredibleBlock(block.number - (THRESHOLD + 1));

        assertTrue(vault.failOpenActive());
        assertTrue(vault.isCurrentBlockAllowed());
        vault.doProtectedAction();
        assertEq(vault.actions(), 1);
    }

    function test_failsOpen_whenRegistryNeverMarked_andBeyondThreshold() public {
        // lastCredibleBlock defaults to 0; once current block exceeds the threshold, fail open.
        vm.roll(THRESHOLD + 1);
        assertTrue(vault.failOpenActive());
        vault.doProtectedAction();
        assertEq(vault.actions(), 1);
    }

    function test_reverts_whenRegistryNeverMarked_atThresholdBlock() public {
        // At exactly the threshold block, gap (== block.number) is not strictly greater.
        vm.roll(THRESHOLD);
        assertFalse(vault.failOpenActive());
        vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
        vault.doProtectedAction();
    }

    function test_checksCurrentBlockOnly_notPreviousCredibleBlock() public {
        // Mark block N credible, then advance one block: N+1 is not credible and still within
        // the live window, so the guard blocks.
        registry.markCurrentBlockCredible();
        vm.roll(block.number + 1);

        vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
        vault.doProtectedAction();
    }

    // ---------------------------------------------------------------------
    // Defensive: registry reports a last credible block at/after current block
    // ---------------------------------------------------------------------

    function test_noUnderflow_whenLastCredibleBlockInFuture() public {
        registry.setLastCredibleBlock(block.number + 5);
        // Not fail open, current block not credible -> clean NonCredibleBlock revert, no panic.
        vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
        vault.doProtectedAction();
    }

    // ---------------------------------------------------------------------
    // End-to-end builder stall then recover
    // ---------------------------------------------------------------------

    function test_endToEnd_builderStallThenRecover() public {
        // Builder healthy: this block is credible -> allowed.
        registry.markCurrentBlockCredible();
        vault.doProtectedAction();

        // Builder misses a few blocks but is still within the live window -> blocked.
        vm.roll(block.number + 10);
        vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
        vault.doProtectedAction();

        // Builder stays silent past the window -> fail open -> allowed.
        vm.roll(block.number + THRESHOLD);
        vault.doProtectedAction();

        // Builder recovers and marks the new current block -> allowed again.
        registry.markCurrentBlockCredible();
        vault.doProtectedAction();

        assertEq(vault.actions(), 3);
    }

    // ---------------------------------------------------------------------
    // Decision table: allowed == "credible current block OR gap beyond threshold"
    //
    // The gate is fully deterministic, so a fixed table over the boundary-relevant
    // gaps (below / at / above the threshold, with the current block credible or
    // not) gives the same coverage an equivalent fuzz test would. It is kept
    // table-driven rather than fuzzed because this directory is gated by the
    // `pcl test` runner, whose fuzzing worker overflows its stack and aborts the
    // whole protection job.
    // ---------------------------------------------------------------------

    function test_decisionMatchesSpec_acrossGaps() public {
        uint256[6] memory gaps = [uint256(0), 1, THRESHOLD - 1, THRESHOLD, THRESHOLD + 1, 10 * THRESHOLD];

        for (uint256 i = 0; i < gaps.length; i++) {
            _assertDecision(gaps[i], false);
            _assertDecision(gaps[i], true);
        }
    }

    /// @dev Asserts the gate's decision for one (gap, currentCredible) case. Uses fresh
    ///      instances so each case starts from a clean slate, exactly as a fuzz run would.
    function _assertDecision(uint256 gap, bool currentCredible) internal {
        MockCredibleRegistry reg = new MockCredibleRegistry();
        GuardedVault v = new GuardedVault(reg, THRESHOLD);

        // BASE_BLOCK is large enough that block.number - gap never underflows.
        reg.setLastCredibleBlock(block.number - gap);
        if (currentCredible) reg.setCredibleBlock(block.number, true);

        bool failOpen = gap > THRESHOLD; // block.number > last is guaranteed for gap > 0
        bool expectedAllowed = failOpen || currentCredible;

        assertEq(v.failOpenActive(), failOpen);
        assertEq(v.isCurrentBlockAllowed(), expectedAllowed);

        if (expectedAllowed) {
            v.doProtectedAction();
            assertEq(v.actions(), 1);
        } else {
            vm.expectRevert(CredibleBlockGuard.NonCredibleBlock.selector);
            v.doProtectedAction();
            assertEq(v.actions(), 0);
        }
    }
}
