// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {ISymbioticVaultLike} from "./SymbioticInterfaces.sol";
import {SymbioticVaultBaseAssertion} from "./SymbioticVaultBaseAssertion.sol";
import {SymbioticVaultFlowHelpers} from "./SymbioticVaultFlowHelpers.sol";

/// @title SymbioticVaultFlowAssertion
/// @author Phylax Systems
/// @notice Assertions for Symbiotic Core vault deposit, withdraw, redeem, and claim flow.
/// @dev These checks target the base Symbiotic vault flow used by relay auto-deployed vaults.
///
///      - protects against deposits minting the wrong amount of stake or shares;
///      - protects against withdraw/redeem paying out immediately instead of queueing;
///      - protects against claims for immature or already-claimed epochs;
///      - protects against drift between `totalStake` and the vault's internal stake buckets.
abstract contract SymbioticVaultFlowAssertion is SymbioticVaultFlowHelpers {
    /// @notice Register the standard Symbiotic vault flow triggers.
    /// @dev Use per-call triggers for user operations where we need precise pre/post-call deltas,
    ///      and a tx-end trigger for the global `totalStake` bucket identity.
    function _registerVaultFlowTriggers() internal view {
        registerFnCallTrigger(this.assertDepositAccounting.selector, ISymbioticVaultLike.deposit.selector);
        registerFnCallTrigger(this.assertWithdrawScheduling.selector, ISymbioticVaultLike.withdraw.selector);
        registerFnCallTrigger(this.assertRedeemScheduling.selector, ISymbioticVaultLike.redeem.selector);
        registerFnCallTrigger(this.assertClaimFlow.selector, ISymbioticVaultLike.claim.selector);
        registerFnCallTrigger(this.assertClaimBatchFlow.selector, ISymbioticVaultLike.claimBatch.selector);
        registerTxEndTrigger(this.assertTotalStakeIdentity.selector);
    }

    /// @notice Successful deposits must match token/accounting deltas and vault policy.
    /// @dev Protects against deposits that move collateral but mis-account stake or shares.
    ///      After a successful deposit, the reported return values must match the observed deltas.
    function assertDepositAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.TriggerCall memory call_ = _currentTriggerCall(vault, ctx);
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address onBehalfOf,) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        (uint256 depositedAmount, uint256 mintedShares) = abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        DepositDeltas memory deltas = _depositDeltasAt(onBehalfOf, preFork, postFork);
        uint256 postActiveStake = _activeStakeAt(vault, postFork);

        require(deltas.assetDelta == depositedAmount, "SymbioticVault: deposit asset delta mismatch");
        require(deltas.activeStakeDelta == depositedAmount, "SymbioticVault: deposit activeStake mismatch");
        require(deltas.activeSharesDelta == mintedShares, "SymbioticVault: deposit activeShares mismatch");
        require(deltas.beneficiarySharesDelta == mintedShares, "SymbioticVault: deposit beneficiary shares mismatch");

        _assertDepositPolicy(call_.caller, preFork, postFork, postActiveStake);
    }

    /// @notice Withdrawals must queue assets into next epoch without moving collateral immediately.
    /// @dev Protects against a vault paying collateral out too early or minting the wrong queued claim state.
    ///      After a successful withdraw, active stake/shares should go down and next-epoch claims should go up.
    function assertWithdrawScheduling() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address claimer, uint256 amount) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        (uint256 burnedShares, uint256 mintedWithdrawalShares) =
            abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        uint256 nextEpoch = _currentEpochAt(vault, preFork) + 1;

        QueueDeltas memory deltas = _queueDeltasAt(claimer, nextEpoch, preFork, postFork);

        _assertNoImmediateCollateralOutflow(
            preFork, postFork, "SymbioticVault: withdraw moved collateral immediately"
        );
        require(deltas.activeStakeReduction == amount, "SymbioticVault: withdraw activeStake mismatch");
        require(deltas.activeSharesReduction == burnedShares, "SymbioticVault: withdraw burned shares mismatch");
        require(deltas.queuedAssetsIncrease == amount, "SymbioticVault: withdraw next-epoch withdrawals mismatch");
        require(deltas.queuedSharesIncrease == mintedWithdrawalShares, "SymbioticVault: withdraw epoch share mint mismatch");
        require(
            deltas.claimerQueuedSharesIncrease == mintedWithdrawalShares,
            "SymbioticVault: withdraw claimer share mint mismatch"
        );
    }

    /// @notice Redeems must mirror withdraw scheduling and avoid immediate asset outflow.
    /// @dev Protects against share-based exits bypassing the normal withdrawal queue.
    ///      After a successful redeem, the vault should only reshuffle internal buckets for the next epoch.
    function assertRedeemScheduling() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address claimer, uint256 shares) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        (uint256 withdrawnAssets, uint256 mintedWithdrawalShares) =
            abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        uint256 nextEpoch = _currentEpochAt(vault, preFork) + 1;

        QueueDeltas memory deltas = _queueDeltasAt(claimer, nextEpoch, preFork, postFork);

        _assertNoImmediateCollateralOutflow(preFork, postFork, "SymbioticVault: redeem moved collateral immediately");
        require(deltas.activeSharesReduction == shares, "SymbioticVault: redeem activeShares mismatch");
        require(deltas.activeStakeReduction == withdrawnAssets, "SymbioticVault: redeem withdrawn assets mismatch");
        require(deltas.queuedAssetsIncrease == withdrawnAssets, "SymbioticVault: redeem withdrawals mismatch");
        require(deltas.queuedSharesIncrease == mintedWithdrawalShares, "SymbioticVault: redeem epoch share mint mismatch");
        require(
            deltas.claimerQueuedSharesIncrease == mintedWithdrawalShares,
            "SymbioticVault: redeem claimer share mint mismatch"
        );
    }

    /// @notice Mature claims must pay exactly the amount reported by the vault and mark the epoch claimed.
    /// @dev Protects against early, duplicate, underpaid, or untracked claims.
    ///      After a successful claim, one mature epoch should be paid exactly once and marked claimed.
    function assertClaimFlow() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.TriggerCall memory call_ = _currentTriggerCall(vault, ctx);
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address recipient, uint256 epoch) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        uint256 claimedAmount = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));
        ClaimDeltas memory deltas = _claimDeltasAt(recipient, preFork, postFork);

        require(epoch < _currentEpochAt(vault, preFork), "SymbioticVault: claim succeeded for immature epoch");
        require(deltas.vaultOutflow == claimedAmount, "SymbioticVault: claim vault outflow mismatch");
        require(deltas.recipientInflow == claimedAmount, "SymbioticVault: claim recipient inflow mismatch");
        _assertClaimStateTransition(epoch, call_.caller, preFork, postFork, false);
    }

    /// @notice Batch claims must only include mature epochs and pay exact collateral.
    /// @dev Protects against a batch claim sneaking in immature epochs or failing to mark epochs as consumed.
    ///      After a successful batch claim, every epoch in the batch must be mature, newly claimed, and fully paid.
    function assertClaimBatchFlow() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.TriggerCall memory call_ = _currentTriggerCall(vault, ctx);
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address recipient, uint256[] memory epochs) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256[]));
        uint256 claimedAmount = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));
        ClaimDeltas memory deltas = _claimDeltasAt(recipient, preFork, postFork);
        uint256 currentEpoch = _currentEpochAt(vault, preFork);

        require(deltas.vaultOutflow == claimedAmount, "SymbioticVault: claimBatch vault outflow mismatch");
        require(deltas.recipientInflow == claimedAmount, "SymbioticVault: claimBatch recipient inflow mismatch");

        for (uint256 i; i < epochs.length; ++i) {
            require(epochs[i] < currentEpoch, "SymbioticVault: claimBatch succeeded for immature epoch");
            _assertClaimStateTransition(epochs[i], call_.caller, preFork, postFork, true);
        }
    }

    /// @notice Symbiotic vault total stake must equal active stake plus current and next epoch withdrawals.
    /// @dev Protects against the vault's aggregate stake drifting away from its three storage buckets.
    ///      After any transaction, all stake should live in exactly one of: active, current queued, next queued.
    function assertTotalStakeIdentity() external view {
        PhEvm.ForkId memory postTx = _postTx();
        uint256 epoch = _currentEpochAt(vault, postTx);
        uint256 totalStake = _totalStakeAt(vault, postTx);
        uint256 activeStake = _activeStakeAt(vault, postTx);
        uint256 currentWithdrawals = _withdrawalsAt(vault, epoch, postTx);
        uint256 nextWithdrawals = _withdrawalsAt(vault, epoch + 1, postTx);

        // In the base Symbiotic vault flow, stake lives in three buckets:
        // active now, queued for the current epoch, and queued for the next epoch.
        require(
            totalStake == activeStake + currentWithdrawals + nextWithdrawals,
            "SymbioticVault: totalStake identity broken"
        );
    }

}

/// @title SymbioticVaultProtection
/// @notice Ready-to-use bundle for Symbiotic Core vault-flow assertions.
/// @dev Use this when you only want deposit/withdraw/claim accounting checks without the
///      config-policy or circuit-breaker layers.
contract SymbioticVaultProtection is SymbioticVaultFlowAssertion {
    constructor(address vault_) SymbioticVaultBaseAssertion(vault_) {}

    /// @notice Wires only the vault-flow triggers.
    /// @dev This bundle protects the happy-path accounting surface: deposit, withdraw, redeem,
    ///      claim, claimBatch, and the tx-wide total-stake identity.
    function triggers() external view override {
        _registerVaultFlowTriggers();
    }
}
