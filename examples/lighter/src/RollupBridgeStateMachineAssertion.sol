// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

/// @title RollupBridgeStateMachineAssertion
/// @author Phylax Systems
/// @notice Reusable base for L1 bridge contracts of zkSync-lineage validity rollups (zkSync Era,
///         Scroll, Lighter, and similar). These bridges custody user funds on L1 and advance a
///         three-stage block/batch state machine — `committed -> verified -> executed` — alongside
///         a `committed -> verified -> executed` priority-request queue for L1->L2 deposits and
///         forced transactions.
///
/// What this base protects (and why the contract cannot enforce it on-chain by itself):
///   - Each individual entry point (commit/verify/execute/revert) only guards its own local
///     transition with `require`s. No single function asserts the *holistic* relationship across
///     all six counters and the state root as a postcondition, and doing so on-chain on every call
///     would be redundant gas. A runtime monitor checks the whole envelope across every code path.
///   - These bridges are operated by a small trusted validator set behind an upgradeable proxy. A
///     compromised validator or a malicious/buggy upgrade can write the counters and state root
///     directly, bypassing the local `require`s the contract relies on. An assertion observing the
///     pre/post state of the proxy constrains even the privileged paths the contract itself trusts.
///
/// Invariants:
///   - **Ordering**: `executed <= verified <= committed` for batches. Priority execution is also
///     bounded by verification in active mode and by commitment during desert cancellation.
///   - **Finality**: executed counters never decrease. Verified-but-unexecuted state may be rolled
///     back by the official `revertBatches` path.
///   - **State-root continuity**: the executed state root may only change when the executed-batch
///     count advanced (the normal execute path), or when an authorized one-shot state-root
///     migration call was made in the same transaction. Any other state-root mutation is an operator
///     silently rewriting account balances.
///
/// @dev Storage-layout-agnostic: a concrete rollup implementation supplies the read by overriding
///      `_readRollupState`, and names its privileged migration selector via
///      `_stateRootUpdateSelector`. Inherit this base, implement those two hooks, then call
///      `_registerStateMachineTriggers()` from `triggers()`.
abstract contract RollupBridgeStateMachineAssertion is Assertion {
    /// @notice Snapshot of the rollup state machine read at a single fork point.
    /// @dev `inDesertMode` is included for derived contracts that model an escape hatch; the base
    ///      invariants here do not depend on it.
    struct RollupState {
        uint256 committedBatches;
        uint256 verifiedBatches;
        uint256 executedBatches;
        uint256 committedPriorityRequests;
        uint256 verifiedPriorityRequests;
        uint256 executedPriorityRequests;
        uint256 openPriorityRequests;
        bytes32 stateRoot;
        bool inDesertMode;
    }

    /// @notice Reads the rollup state machine at a snapshot fork.
    /// @dev Implement against the concrete bridge — via public getters read with `ph.staticcallAt`
    ///      or via raw storage slots read with `ph.loadStateAt`. Must populate every counter, the
    ///      executed state root, and the desert-mode flag.
    function _readRollupState(PhEvm.ForkId memory fork) internal view virtual returns (RollupState memory state);

    /// @notice The 4-byte selector of the privileged one-shot state-root migration entry point.
    /// @dev Return `bytes4(0)` if the bridge has no such function; then any state-root change with
    ///      no executed-batch advance is treated as a violation. Lighter's is `updateStateRoot`.
    function _stateRootUpdateSelector() internal pure virtual returns (bytes4 selector);

    /// @notice Registers the three transaction-end state-machine checks.
    /// @dev These are envelope invariants over the whole transaction, so each uses a tx-end trigger.
    ///      Call this from the concrete assertion's `triggers()`.
    function _registerStateMachineTriggers() internal view {
        registerTxEndTrigger(this.assertBatchOrdering.selector);
        registerTxEndTrigger(this.assertFinalityNonDecreasing.selector);
        registerTxEndTrigger(this.assertStateRootContinuity.selector);
    }

    /// @notice Batch and priority-request counters obey `executed <= verified <= committed`.
    /// @dev Checked on the post-transaction state, which is the state that governs which funds are
    ///      withdrawable. A failure means the bridge ended the transaction able to execute (pay out)
    ///      more than it has verified, or verify more than it has committed — i.e. funds finalized
    ///      against state that was never proven. Also requires the open priority queue to cover every
    ///      committed-but-unexecuted request, so no queued L1->L2 deposit can be dropped from the
    ///      accounting.
    function assertBatchOrdering() external view {
        RollupState memory post = _readRollupState(_postTx());

        require(post.verifiedBatches <= post.committedBatches, "RollupBridge: verified exceeds committed batches");
        require(post.executedBatches <= post.verifiedBatches, "RollupBridge: executed exceeds verified batches");

        require(
            post.verifiedPriorityRequests <= post.committedPriorityRequests,
            "RollupBridge: verified exceeds committed priority"
        );
        if (post.inDesertMode) {
            require(
                post.executedPriorityRequests <= post.committedPriorityRequests,
                "RollupBridge: executed exceeds committed priority"
            );
        } else {
            require(
                post.executedPriorityRequests <= post.verifiedPriorityRequests,
                "RollupBridge: executed exceeds verified priority"
            );
        }

        // Committed-but-unexecuted priority requests must still be open. Otherwise a queued deposit
        // or forced transaction has been committed yet dropped from the open queue.
        require(
            post.committedPriorityRequests - post.executedPriorityRequests <= post.openPriorityRequests,
            "RollupBridge: open queue underflows committed priority"
        );
    }

    /// @notice Executed counters never decrease across the transaction.
    /// @dev Lighter may revert verified-but-unexecuted batches and priority requests. Execution is
    ///      the final boundary that the official rollback path cannot cross.
    function assertFinalityNonDecreasing() external view {
        RollupState memory pre = _readRollupState(_preTx());
        RollupState memory post = _readRollupState(_postTx());

        require(post.executedBatches >= pre.executedBatches, "RollupBridge: executed batches decreased");
        require(
            post.executedPriorityRequests >= pre.executedPriorityRequests, "RollupBridge: executed priority decreased"
        );
    }

    /// @notice The executed state root only changes through finality advance or an authorized migration.
    /// @dev If the state root moved but no batch was executed (`executedBatches` unchanged) and no
    ///      authorized state-root migration call was made this transaction, the operator rewrote the
    ///      committed account state out of band — the most direct way to steal every user's balance.
    ///      The migration exception covers the rare proof-gated root-replacement path that legitimately
    ///      changes the root without executing a batch.
    function assertStateRootContinuity() external view {
        RollupState memory pre = _readRollupState(_preTx());
        RollupState memory post = _readRollupState(_postTx());

        if (post.stateRoot == pre.stateRoot) {
            return;
        }

        if (post.executedBatches > pre.executedBatches) {
            return;
        }

        require(_stateRootMigrationOccurred(), "RollupBridge: state root changed without execution");
    }

    /// @notice Detects whether an authorized one-shot state-root migration call hit the bridge.
    /// @dev The bridge is the assertion adopter. Matches by selector only and checks for presence,
    ///      so it does not depend on decoding the (proof-bearing) calldata. Returns false when the
    ///      bridge exposes no migration selector.
    function _stateRootMigrationOccurred() internal view returns (bool) {
        bytes4 selector = _stateRootUpdateSelector();
        if (selector == bytes4(0)) {
            return false;
        }
        return ph.getCallInputs(ph.getAssertionAdopter(), selector).length > 0;
    }
}
