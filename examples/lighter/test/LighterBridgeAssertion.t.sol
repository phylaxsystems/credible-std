// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {RollupBridgeStateMachineAssertion} from "../src/RollupBridgeStateMachineAssertion.sol";
import {LighterBridgeAssertion} from "../src/LighterBridgeAssertion.sol";
import {IZkLighterLike} from "../src/LighterBridgeInterfaces.sol";

/// @notice Minimal stand-in for Lighter's `ZkLighter` bridge. Holds the rollup state machine in plain
///         storage behind the `IZkLighterLike` getters, plus one mutation per failure mode so each
///         behavior test trips exactly one invariant.
contract MockZkLighter is IZkLighterLike {
    uint256 internal _committedBatches;
    uint256 internal _verifiedBatches;
    uint256 internal _executedBatches;
    uint256 internal _committedPriority;
    uint256 internal _verifiedPriority;
    uint256 internal _executedPriority;
    uint256 internal _openPriority;
    bytes32 internal _stateRoot;
    bool internal _desertMode;

    function seed(
        uint256 committedBatches_,
        uint256 verifiedBatches_,
        uint256 executedBatches_,
        uint256 committedPriority_,
        uint256 verifiedPriority_,
        uint256 executedPriority_,
        uint256 openPriority_,
        bytes32 stateRoot_,
        bool desertMode_
    ) external {
        _committedBatches = committedBatches_;
        _verifiedBatches = verifiedBatches_;
        _executedBatches = executedBatches_;
        _committedPriority = committedPriority_;
        _verifiedPriority = verifiedPriority_;
        _executedPriority = executedPriority_;
        _openPriority = openPriority_;
        _stateRoot = stateRoot_;
        _desertMode = desertMode_;
    }

    // --- Honest mutations -------------------------------------------------

    /// @notice Commit a batch and the priority requests it consumes.
    function commit(uint256 batches, uint256 priority) external {
        _committedBatches += batches;
        _committedPriority += priority;
    }

    /// @notice Verify already-committed batches/priority (stays within committed bounds).
    function verify(uint256 batches, uint256 priority) external {
        _verifiedBatches += batches;
        _verifiedPriority += priority;
    }

    /// @notice Execute verified batches: advances finality and moves the state root.
    function execute(uint256 batches, uint256 priority, bytes32 newRoot) external {
        _executedBatches += batches;
        _executedPriority += priority;
        if (_openPriority >= priority) {
            _openPriority -= priority;
        }
        _stateRoot = newRoot;
    }

    /// @notice Privileged one-shot state-root migration: moves the root with no executed advance.
    function updateStateRoot(bytes32, bytes32, bytes32 newStateRoot, bytes calldata) external {
        _stateRoot = newStateRoot;
    }

    function activateDesertMode() external {
        _desertMode = true;
    }

    // --- Malicious / buggy mutations (one knob per failure mode) -----------

    function forceVerifyBeyondCommitted() external {
        _verifiedBatches = _committedBatches + 1;
    }

    function rollbackExecutedBatch() external {
        _executedBatches -= 1;
    }

    function rewriteStateRoot(bytes32 root) external {
        _stateRoot = root;
    }

    function reopenOperator() external {
        _desertMode = false;
    }

    // --- IZkLighterLike getters -------------------------------------------

    function committedBatchesCount() external view returns (uint256) {
        return _committedBatches;
    }

    function verifiedBatchesCount() external view returns (uint256) {
        return _verifiedBatches;
    }

    function executedBatchesCount() external view returns (uint256) {
        return _executedBatches;
    }

    function committedPriorityRequestCount() external view returns (uint256) {
        return _committedPriority;
    }

    function verifiedPriorityRequestCount() external view returns (uint256) {
        return _verifiedPriority;
    }

    function executedPriorityRequestCount() external view returns (uint256) {
        return _executedPriority;
    }

    function openPriorityRequestCount() external view returns (uint256) {
        return _openPriority;
    }

    function stateRoot() external view returns (bytes32) {
        return _stateRoot;
    }

    function desertMode() external view returns (bool) {
        return _desertMode;
    }
}

contract LighterBridgeAssertionTest is Test, CredibleTest {
    bytes32 internal constant ROOT_A = keccak256("root-a");
    bytes32 internal constant ROOT_B = keccak256("root-b");

    MockZkLighter internal bridge;

    function setUp() public {
        bridge = new MockZkLighter();
        // Baseline consistent state machine: executed <= verified <= committed, open covers
        // committed-but-unexecuted priority requests.
        bridge.seed(10, 8, 6, 10, 8, 6, 4, ROOT_A, false);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData =
            abi.encodePacked(type(LighterBridgeAssertion).creationCode, abi.encode(address(bridge)));
        cl.assertion(address(bridge), createData, fnSelector);
    }

    // --- Batch ordering ---------------------------------------------------

    function testOrderingHonestVerifyPasses() public {
        _arm(RollupBridgeStateMachineAssertion.assertBatchOrdering.selector);
        bridge.verify(1, 1); // verified 8->9 <= committed 10
    }

    function testOrderingVerifyBeyondCommittedTrips() public {
        _arm(RollupBridgeStateMachineAssertion.assertBatchOrdering.selector);
        vm.expectRevert(bytes("RollupBridge: verified exceeds committed batches"));
        bridge.forceVerifyBeyondCommitted(); // verified -> 11 > committed 10
    }

    // --- Finality non-decrease --------------------------------------------

    function testFinalityHonestExecutePasses() public {
        _arm(RollupBridgeStateMachineAssertion.assertFinalityNonDecreasing.selector);
        bridge.execute(1, 1, ROOT_B); // executed 6->7
    }

    function testFinalityExecutedRollbackTrips() public {
        _arm(RollupBridgeStateMachineAssertion.assertFinalityNonDecreasing.selector);
        vm.expectRevert(bytes("RollupBridge: executed batches decreased"));
        bridge.rollbackExecutedBatch(); // executed 6->5
    }

    // --- State-root continuity --------------------------------------------

    function testStateRootHonestExecuteAdvancePasses() public {
        _arm(RollupBridgeStateMachineAssertion.assertStateRootContinuity.selector);
        bridge.execute(1, 1, ROOT_B); // root changes, executed advanced
    }

    function testStateRootAuthorizedMigrationPasses() public {
        _arm(RollupBridgeStateMachineAssertion.assertStateRootContinuity.selector);
        // Root moves with no executed advance, but through the authorized migration selector.
        bridge.updateStateRoot(ROOT_A, bytes32(0), ROOT_B, hex"");
    }

    function testStateRootRewriteWithoutExecutionTrips() public {
        _arm(RollupBridgeStateMachineAssertion.assertStateRootContinuity.selector);
        vm.expectRevert(bytes("RollupBridge: state root changed without execution"));
        bridge.rewriteStateRoot(ROOT_B); // root changes, executed unchanged, no migration call
    }

    // --- Desert-mode integrity --------------------------------------------

    function testDesertActivationFromActiveStatePasses() public {
        _arm(LighterBridgeAssertion.assertDesertModeIntegrity.selector);
        bridge.activateDesertMode(); // pre: not desert -> freeze checks skipped
    }

    function testDesertModeExitTrips() public {
        bridge.seed(10, 8, 6, 10, 8, 6, 4, ROOT_A, true); // already in desert mode
        _arm(LighterBridgeAssertion.assertDesertModeIntegrity.selector);
        vm.expectRevert(bytes("LighterBridge: desert mode exited"));
        bridge.reopenOperator(); // desert true -> false
    }

    function testDesertModeOperatorFreezeTrips() public {
        bridge.seed(10, 8, 6, 10, 8, 6, 4, ROOT_A, true); // already in desert mode
        _arm(LighterBridgeAssertion.assertDesertModeIntegrity.selector);
        vm.expectRevert(bytes("LighterBridge: committed advanced in desert mode"));
        bridge.commit(1, 0); // operator advancing while frozen
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroBridge() public {
        vm.expectRevert(bytes("LighterBridge: bridge zero"));
        new LighterBridgeAssertion(address(0));
    }
}
