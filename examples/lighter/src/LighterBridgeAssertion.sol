// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {LighterBridgeHelpers} from "./LighterBridgeHelpers.sol";

/// @title LighterBridgeAssertion
/// @author Phylax Systems
/// @notice Rollup state-machine safety bundle for Lighter's L1 bridge / rollup contract (`ZkLighter`).
///         Lighter is an app-specific ZK validity rollup whose single proxied contract both custodies
///         user funds and advances the `committed -> verified -> executed` batch/priority state
///         machine, with a 14-day-expiry escape hatch ("desert mode").
/// @dev Reuses the `RollupBridgeStateMachineAssertion` base for the generic rollup invariants
///      (ordering, finality non-decrease, state-root continuity) and adds the desert-mode integrity
///      property specific to Lighter's escape hatch. Funds-custody outflow rate limiting is a
///      separate concern handled by `LighterOutflowCircuitBreaker`, deployed alongside this bundle.
///
///      Every property here is one the contract cannot enforce against itself: the invariants span
///      storage the contract only mutates piecewise and trusts its validators/upgrades to keep
///      consistent.
///
///      Remaining risk this bundle does not cover: it does not re-verify ZK proofs, does not validate
///      per-account balance correctness inside the state root, and trusts the `IZkLighterLike` getter
///      surface to reflect the documented storage (verify selectors/layout against the deployment).
contract LighterBridgeAssertion is LighterBridgeHelpers {
    constructor(address bridge_) LighterBridgeHelpers(bridge_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the rollup state-machine envelope checks and the desert-mode check.
    /// @dev All are whole-transaction properties, so they use tx-end triggers.
    function triggers() external view override {
        _registerStateMachineTriggers();
        registerTxEndTrigger(this.assertDesertModeIntegrity.selector);
    }

    /// @notice The escape hatch is latching and freezes the operator while it is open.
    /// @dev Two properties checked at transaction end:
    ///        - **Irreversible**: `desertMode` may never transition from true back to false. Re-enabling
    ///          the operator after users have begun escaping would strand in-flight exits.
    ///        - **Operator frozen**: if the bridge was already in desert mode at the start of the
    ///          transaction, no batch may be committed, verified, or executed and the state root may
    ///          not move. Priority-request counters are intentionally not frozen, because desert-mode
    ///          deposit cancellation legitimately advances the executed-priority counter while
    ///          refunding queued deposits.
    ///      The contract enforces this today only through scattered `onlyActive` modifiers; a single
    ///      upgrade that drops one modifier would reopen the operator mid-escape. This assertion makes
    ///      the freeze a property of the whole transaction instead.
    function assertDesertModeIntegrity() external view {
        RollupState memory pre = _readRollupState(_preTx());
        RollupState memory post = _readRollupState(_postTx());

        require(!(pre.inDesertMode && !post.inDesertMode), "LighterBridge: desert mode exited");

        if (!pre.inDesertMode) {
            if (!post.inDesertMode) return;

            require(pre.openPriorityRequests != 0, "LighterBridge: desert mode activated without open requests");
            require(post.committedBatches == pre.committedBatches, "LighterBridge: committed changed on activation");
            require(post.verifiedBatches == pre.verifiedBatches, "LighterBridge: verified changed on activation");
            require(post.executedBatches == pre.executedBatches, "LighterBridge: executed changed on activation");
            require(
                post.committedPriorityRequests == pre.committedPriorityRequests,
                "LighterBridge: committed priority changed on activation"
            );
            require(
                post.verifiedPriorityRequests == pre.verifiedPriorityRequests,
                "LighterBridge: verified priority changed on activation"
            );
            require(
                post.executedPriorityRequests == pre.executedPriorityRequests,
                "LighterBridge: executed priority changed on activation"
            );
            require(post.openPriorityRequests == pre.openPriorityRequests, "LighterBridge: open queue changed on activation");
            require(post.stateRoot == pre.stateRoot, "LighterBridge: state root changed on activation");
            return;
        }

        require(post.committedBatches == pre.committedBatches, "LighterBridge: committed advanced in desert mode");
        require(post.verifiedBatches == pre.verifiedBatches, "LighterBridge: verified advanced in desert mode");
        require(post.executedBatches == pre.executedBatches, "LighterBridge: executed advanced in desert mode");
        require(post.stateRoot == pre.stateRoot, "LighterBridge: state root moved in desert mode");
        require(
            post.committedPriorityRequests == pre.committedPriorityRequests,
            "LighterBridge: committed priority changed in desert mode"
        );
        require(
            post.verifiedPriorityRequests == pre.verifiedPriorityRequests,
            "LighterBridge: verified priority changed in desert mode"
        );
        require(
            post.openPriorityRequests <= pre.openPriorityRequests,
            "LighterBridge: open priority increased in desert mode"
        );
        require(
            post.executedPriorityRequests - pre.executedPriorityRequests
                == pre.openPriorityRequests - post.openPriorityRequests,
            "LighterBridge: desert cancellation does not conserve priority requests"
        );
    }
}
