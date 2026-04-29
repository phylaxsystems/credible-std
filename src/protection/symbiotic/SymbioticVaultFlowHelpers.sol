// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {SymbioticVaultBaseAssertion} from "./SymbioticVaultBaseAssertion.sol";

/// @title SymbioticVaultFlowHelpers
/// @author Phylax Systems
/// @notice Shared flow-specific structs, delta calculators, and helper checks for Symbiotic vault assertions.
/// @dev Keeps the flow assertion focused on the invariant checks while centralizing the
///      repetitive pre/post accounting reads and small flow-only validation helpers.
abstract contract SymbioticVaultFlowHelpers is SymbioticVaultBaseAssertion {
    struct DepositDeltas {
        uint256 assetDelta;
        uint256 activeStakeDelta;
        uint256 activeSharesDelta;
        uint256 beneficiarySharesDelta;
    }

    struct QueueDeltas {
        uint256 activeStakeReduction;
        uint256 activeSharesReduction;
        uint256 queuedAssetsIncrease;
        uint256 queuedSharesIncrease;
        uint256 claimerQueuedSharesIncrease;
    }

    struct ClaimDeltas {
        uint256 vaultOutflow;
        uint256 recipientInflow;
    }

    function _depositDeltasAt(address onBehalfOf, PhEvm.ForkId memory preFork, PhEvm.ForkId memory postFork)
        internal
        view
        returns (DepositDeltas memory deltas)
    {
        uint256 preAssetBalance = _readBalanceAt(asset, vault, preFork);
        uint256 postAssetBalance = _readBalanceAt(asset, vault, postFork);
        uint256 preActiveStake = _activeStakeAt(vault, preFork);
        uint256 postActiveStake = _activeStakeAt(vault, postFork);
        uint256 preActiveShares = _activeSharesAt(vault, preFork);
        uint256 postActiveShares = _activeSharesAt(vault, postFork);
        uint256 preBeneficiaryShares = _activeSharesOfAt(vault, onBehalfOf, preFork);
        uint256 postBeneficiaryShares = _activeSharesOfAt(vault, onBehalfOf, postFork);

        deltas = DepositDeltas({
            assetDelta: postAssetBalance - preAssetBalance,
            activeStakeDelta: postActiveStake - preActiveStake,
            activeSharesDelta: postActiveShares - preActiveShares,
            beneficiarySharesDelta: postBeneficiaryShares - preBeneficiaryShares
        });
    }

    function _queueDeltasAt(address claimer, uint256 nextEpoch, PhEvm.ForkId memory preFork, PhEvm.ForkId memory postFork)
        internal
        view
        returns (QueueDeltas memory deltas)
    {
        deltas = QueueDeltas({
            activeStakeReduction: _activeStakeAt(vault, preFork) - _activeStakeAt(vault, postFork),
            activeSharesReduction: _activeSharesAt(vault, preFork) - _activeSharesAt(vault, postFork),
            queuedAssetsIncrease: _withdrawalsAt(vault, nextEpoch, postFork) - _withdrawalsAt(vault, nextEpoch, preFork),
            queuedSharesIncrease: _withdrawalSharesAt(vault, nextEpoch, postFork)
                - _withdrawalSharesAt(vault, nextEpoch, preFork),
            claimerQueuedSharesIncrease: _withdrawalSharesOfAt(vault, nextEpoch, claimer, postFork)
                - _withdrawalSharesOfAt(vault, nextEpoch, claimer, preFork)
        });
    }

    function _claimDeltasAt(address recipient, PhEvm.ForkId memory preFork, PhEvm.ForkId memory postFork)
        internal
        view
        returns (ClaimDeltas memory deltas)
    {
        deltas = ClaimDeltas({
            vaultOutflow: _readBalanceAt(asset, vault, preFork) - _readBalanceAt(asset, vault, postFork),
            recipientInflow: _readBalanceAt(asset, recipient, postFork) - _readBalanceAt(asset, recipient, preFork)
        });
    }

    function _assertDepositPolicy(address caller, PhEvm.ForkId memory preFork, PhEvm.ForkId memory postFork, uint256 postActiveStake)
        internal
        view
    {
        if (_depositWhitelistAt(vault, preFork)) {
            require(
                _isDepositorWhitelistedAt(vault, caller, preFork),
                "SymbioticVault: successful deposit by non-whitelisted caller"
            );
        }

        if (_isDepositLimitAt(vault, postFork)) {
            require(
                postActiveStake <= _depositLimitAt(vault, postFork),
                "SymbioticVault: deposit limit exceeded after deposit"
            );
        }
    }

    function _assertNoImmediateCollateralOutflow(
        PhEvm.ForkId memory preFork,
        PhEvm.ForkId memory postFork,
        string memory err
    ) internal {
        require(ph.conserveBalance(preFork, postFork, asset, vault), err);
    }

    function _assertClaimStateTransition(
        uint256 epoch,
        address claimant,
        PhEvm.ForkId memory preFork,
        PhEvm.ForkId memory postFork,
        bool isBatch
    ) internal view {
        if (isBatch) {
            require(
                !_isWithdrawalsClaimedAt(vault, epoch, claimant, preFork),
                "SymbioticVault: claimBatch epoch was already claimed before call"
            );
            require(
                _isWithdrawalsClaimedAt(vault, epoch, claimant, postFork),
                "SymbioticVault: claimBatch epoch not marked claimed"
            );
            return;
        }

        require(
            !_isWithdrawalsClaimedAt(vault, epoch, claimant, preFork),
            "SymbioticVault: claim was already marked claimed before call"
        );
        require(
            _isWithdrawalsClaimedAt(vault, epoch, claimant, postFork),
            "SymbioticVault: claim did not mark epoch claimed"
        );
    }
}
