// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {SymbioticHelpers} from "./SymbioticHelpers.sol";
import {ISymbioticVaultLike} from "./SymbioticInterfaces.sol";

/// @title SymbioticVaultFlowAssertion
/// @author Phylax Systems
/// @notice Assertions for Symbiotic Core vault deposit, withdraw, redeem, and claim flow.
/// @dev These checks target the base Symbiotic vault flow used by relay auto-deployed vaults,
///      not ERC-4626 tokenized vault semantics.
abstract contract SymbioticVaultFlowAssertion is SymbioticHelpers {
    address internal immutable vault;
    address internal immutable asset;

    constructor(address vault_) {
        vault = vault_;
        asset = ISymbioticVaultLike(vault_).collateral();
    }

    /// @notice Register the standard Symbiotic vault flow triggers.
    function _registerVaultFlowTriggers() internal view {
        registerFnCallTrigger(this.assertDepositAccounting.selector, ISymbioticVaultLike.deposit.selector);
        registerFnCallTrigger(this.assertWithdrawScheduling.selector, ISymbioticVaultLike.withdraw.selector);
        registerFnCallTrigger(this.assertRedeemScheduling.selector, ISymbioticVaultLike.redeem.selector);
        registerFnCallTrigger(this.assertClaimFlow.selector, ISymbioticVaultLike.claim.selector);
        registerFnCallTrigger(this.assertClaimBatchFlow.selector, ISymbioticVaultLike.claimBatch.selector);
        registerTxEndTrigger(this.assertTotalStakeIdentity.selector);
    }

    /// @notice Successful deposits must match token/accounting deltas and vault policy.
    function assertDepositAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.TriggerCall memory call_ = _currentTriggerCall(vault, ctx);
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address onBehalfOf,) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        (uint256 depositedAmount, uint256 mintedShares) = abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        uint256 preAssetBalance = _readBalanceAt(asset, vault, preFork);
        uint256 postAssetBalance = _readBalanceAt(asset, vault, postFork);
        uint256 preActiveStake = _activeStakeAt(vault, preFork);
        uint256 postActiveStake = _activeStakeAt(vault, postFork);
        uint256 preActiveShares = _activeSharesAt(vault, preFork);
        uint256 postActiveShares = _activeSharesAt(vault, postFork);
        uint256 preBeneficiaryShares = _activeSharesOfAt(vault, onBehalfOf, preFork);
        uint256 postBeneficiaryShares = _activeSharesOfAt(vault, onBehalfOf, postFork);

        require(postAssetBalance - preAssetBalance == depositedAmount, "SymbioticVault: deposit asset delta mismatch");
        require(postActiveStake - preActiveStake == depositedAmount, "SymbioticVault: deposit activeStake mismatch");
        require(postActiveShares - preActiveShares == mintedShares, "SymbioticVault: deposit activeShares mismatch");
        require(
            postBeneficiaryShares - preBeneficiaryShares == mintedShares,
            "SymbioticVault: deposit beneficiary shares mismatch"
        );

        // A successful deposit through a whitelisted vault implies the caller was allowed to deposit.
        if (_depositWhitelistAt(vault, preFork)) {
            require(
                _isDepositorWhitelistedAt(vault, call_.caller, preFork),
                "SymbioticVault: successful deposit by non-whitelisted caller"
            );
        }

        // Deposit caps are meant to be hard limits on active stake, not advisory config.
        if (_isDepositLimitAt(vault, postFork)) {
            require(
                postActiveStake <= _depositLimitAt(vault, postFork),
                "SymbioticVault: deposit limit exceeded after deposit"
            );
        }
    }

    /// @notice Withdrawals must queue assets into next epoch without moving collateral immediately.
    function assertWithdrawScheduling() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address claimer, uint256 amount) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        (uint256 burnedShares, uint256 mintedWithdrawalShares) =
            abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        uint256 nextEpoch = _currentEpochAt(vault, preFork) + 1;

        // Withdraw queues funds for a later claim; no collateral should leave the vault yet.
        require(
            ph.conserveBalance(preFork, postFork, asset, vault), "SymbioticVault: withdraw moved collateral immediately"
        );
        require(
            _activeStakeAt(vault, preFork) - _activeStakeAt(vault, postFork) == amount,
            "SymbioticVault: withdraw activeStake mismatch"
        );
        require(
            _activeSharesAt(vault, preFork) - _activeSharesAt(vault, postFork) == burnedShares,
            "SymbioticVault: withdraw burned shares mismatch"
        );
        require(
            _withdrawalsAt(vault, nextEpoch, postFork) - _withdrawalsAt(vault, nextEpoch, preFork) == amount,
            "SymbioticVault: withdraw next-epoch withdrawals mismatch"
        );
        require(
            _withdrawalSharesAt(vault, nextEpoch, postFork) - _withdrawalSharesAt(vault, nextEpoch, preFork)
                == mintedWithdrawalShares,
            "SymbioticVault: withdraw epoch share mint mismatch"
        );
        require(
            _withdrawalSharesOfAt(vault, nextEpoch, claimer, postFork)
                    - _withdrawalSharesOfAt(vault, nextEpoch, claimer, preFork) == mintedWithdrawalShares,
            "SymbioticVault: withdraw claimer share mint mismatch"
        );
    }

    /// @notice Redeems must mirror withdraw scheduling and avoid immediate asset outflow.
    function assertRedeemScheduling() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address claimer, uint256 shares) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        (uint256 withdrawnAssets, uint256 mintedWithdrawalShares) =
            abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        uint256 nextEpoch = _currentEpochAt(vault, preFork) + 1;

        // redeem is the share-based version of withdraw: queue now, claim in a later epoch.
        require(
            ph.conserveBalance(preFork, postFork, asset, vault), "SymbioticVault: redeem moved collateral immediately"
        );
        require(
            _activeSharesAt(vault, preFork) - _activeSharesAt(vault, postFork) == shares,
            "SymbioticVault: redeem activeShares mismatch"
        );
        require(
            _activeStakeAt(vault, preFork) - _activeStakeAt(vault, postFork) == withdrawnAssets,
            "SymbioticVault: redeem withdrawn assets mismatch"
        );
        require(
            _withdrawalsAt(vault, nextEpoch, postFork) - _withdrawalsAt(vault, nextEpoch, preFork) == withdrawnAssets,
            "SymbioticVault: redeem withdrawals mismatch"
        );
        require(
            _withdrawalSharesAt(vault, nextEpoch, postFork) - _withdrawalSharesAt(vault, nextEpoch, preFork)
                == mintedWithdrawalShares,
            "SymbioticVault: redeem epoch share mint mismatch"
        );
        require(
            _withdrawalSharesOfAt(vault, nextEpoch, claimer, postFork)
                    - _withdrawalSharesOfAt(vault, nextEpoch, claimer, preFork) == mintedWithdrawalShares,
            "SymbioticVault: redeem claimer share mint mismatch"
        );
    }

    /// @notice Mature claims must pay exactly the amount reported by the vault and mark the epoch claimed.
    function assertClaimFlow() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.TriggerCall memory call_ = _currentTriggerCall(vault, ctx);
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address recipient, uint256 epoch) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));
        uint256 claimedAmount = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        // Claims should only succeed once the withdrawal epoch is already in the past.
        require(epoch < _currentEpochAt(vault, preFork), "SymbioticVault: claim succeeded for immature epoch");
        require(
            _readBalanceAt(asset, vault, preFork) - _readBalanceAt(asset, vault, postFork) == claimedAmount,
            "SymbioticVault: claim vault outflow mismatch"
        );
        require(
            _readBalanceAt(asset, recipient, postFork) - _readBalanceAt(asset, recipient, preFork) == claimedAmount,
            "SymbioticVault: claim recipient inflow mismatch"
        );
        require(
            !_isWithdrawalsClaimedAt(vault, epoch, call_.caller, preFork),
            "SymbioticVault: claim was already marked claimed before call"
        );
        require(
            _isWithdrawalsClaimedAt(vault, epoch, call_.caller, postFork),
            "SymbioticVault: claim did not mark epoch claimed"
        );
    }

    /// @notice Batch claims must only include mature epochs and pay exact collateral.
    function assertClaimBatchFlow() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.TriggerCall memory call_ = _currentTriggerCall(vault, ctx);
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);
        (address recipient, uint256[] memory epochs) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256[]));
        uint256 claimedAmount = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        uint256 currentEpoch = _currentEpochAt(vault, preFork);

        // Batch claims are still exact claims: the vault outflow and recipient inflow must match the reported amount.
        require(
            _readBalanceAt(asset, vault, preFork) - _readBalanceAt(asset, vault, postFork) == claimedAmount,
            "SymbioticVault: claimBatch vault outflow mismatch"
        );
        require(
            _readBalanceAt(asset, recipient, postFork) - _readBalanceAt(asset, recipient, preFork) == claimedAmount,
            "SymbioticVault: claimBatch recipient inflow mismatch"
        );

        for (uint256 i; i < epochs.length; ++i) {
            require(epochs[i] < currentEpoch, "SymbioticVault: claimBatch succeeded for immature epoch");
            require(
                !_isWithdrawalsClaimedAt(vault, epochs[i], call_.caller, preFork),
                "SymbioticVault: claimBatch epoch was already claimed before call"
            );
            require(
                _isWithdrawalsClaimedAt(vault, epochs[i], call_.caller, postFork),
                "SymbioticVault: claimBatch epoch not marked claimed"
            );
        }
    }

    /// @notice Symbiotic vault total stake must equal active stake plus current and next epoch withdrawals.
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
contract SymbioticVaultProtection is SymbioticVaultFlowAssertion {
    constructor(address vault_) SymbioticVaultFlowAssertion(vault_) {}

    function triggers() external view override {
        _registerVaultFlowTriggers();
    }
}
