// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {MellowCuratorHelpers} from "./MellowCuratorHelpers.sol";

/// @title MellowRiskManagerBalanceAssertion
/// @author Phylax Systems
/// @notice Bounds the magnitude of a single trusted balance correction on a Mellow RiskManager.
/// @dev Apply to the `RiskManager`.
///
///      `modifyVaultBalance` / `modifySubvaultBalance` are documented as rare, trusted accounting
///      corrections. They convert a signed asset-denominated delta to shares and add it to the
///      tracked (sub)vault balance. Crucially, the protocol bounds only the *positive* direction:
///      the `LimitExceeded` check fires solely when `change > 0` and the new balance would exceed
///      the configured limit. A negative correction — draining the accounted balance toward zero or
///      negative — is completely unbounded on-chain. A stolen key holding `MODIFY_VAULT_BALANCE_ROLE`
///      / `MODIFY_SUBVAULT_BALANCE_ROLE` could therefore zero out or wildly inflate the vault's
///      accounting in one call, corrupting every downstream conversion (deposits, limits, redeem
///      pricing). This assertion adds the missing magnitude bound, in both directions.
///
///      The bound is relative to the pre-call accounted balance, with an absolute floor so that
///      genuine corrections on a small or freshly-initialized balance are still possible (a purely
///      relative bound would forbid any correction when the balance is near zero). Both knobs are
///      set generously: this catches a catastrophic single-call rewrite, not routine post-report
///      drift reconciliation.
///
///      Ceiling, stated honestly: this does not judge whether a correction is *correct* (it cannot —
///      the true value lives off-chain in restaking positions). It only caps how much a single
///      privileged call may move the accounting, bounding the blast radius of a stolen role.
contract MellowRiskManagerBalanceAssertion is MellowCuratorHelpers {
    /// @notice RiskManager whose balance corrections are bounded (the assertion adopter).
    address public immutable riskManager;

    /// @notice Maximum single-call change as bps of the pre-call accounted balance magnitude.
    ///         CALIBRATE: above the largest legitimate single reconciliation (e.g. 2000 = 20%).
    uint256 public immutable maxModifyBps;

    /// @notice Absolute change (in shares) always permitted regardless of the relative bound, so a
    ///         small or just-initialized balance can still be corrected.
    ///         CALIBRATE: the largest correction expected on a near-zero balance for the deployment.
    uint256 public immutable absoluteFloorShares;

    constructor(address riskManager_, uint256 maxModifyBps_, uint256 absoluteFloorShares_) {
        require(riskManager_ != address(0), "MellowRisk: zero risk manager");
        require(maxModifyBps_ != 0, "MellowRisk: zero modify bps");

        riskManager = riskManager_;
        maxModifyBps = maxModifyBps_;
        absoluteFloorShares = absoluteFloorShares_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Quarantined: these methods are routine queue and strategy accounting hot paths.
    function triggers() external view override {
        // Intentionally empty. A per-call percentage cap rejects valid deposits, redeems, pushes,
        // and pulls while repeated calls can still bypass the intended transaction-wide bound.
    }

    /// @notice Bounds the change to the vault's accounted balance from one `modifyVaultBalance` call.
    /// @dev Compares `vaultState().balance` at the pre-call and post-call snapshots. A failure means
    ///      a single correction moved the vault accounting more than the configured envelope allows.
    function assertVaultBalanceModifyBounded() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        int256 pre = _readVaultBalanceShares(riskManager, _preCall(ctx.callStart));
        int256 post = _readVaultBalanceShares(riskManager, _postCall(ctx.callEnd));
        _requireBoundedDelta(pre, post, "MellowRisk: vault balance correction exceeds bound");
    }

    /// @notice Bounds the change to a subvault's accounted balance from one `modifySubvaultBalance`
    ///         call.
    /// @dev Decodes the subvault address from the call's first argument, then compares
    ///      `subvaultState(subvault).balance` across the pre/post-call snapshots. A failure means a
    ///      single correction moved that subvault's accounting beyond the configured envelope.
    function assertSubvaultBalanceModifyBounded() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        address subvault = _callArgAddress(ctx.callStart, 0);
        int256 pre = _readSubvaultBalanceShares(riskManager, subvault, _preCall(ctx.callStart));
        int256 post = _readSubvaultBalanceShares(riskManager, subvault, _postCall(ctx.callEnd));
        _requireBoundedDelta(pre, post, "MellowRisk: subvault balance correction exceeds bound");
    }

    /// @notice Reverts when the accounted-balance change exceeds `max(absoluteFloor, bps * |pre|)`.
    function _requireBoundedDelta(int256 pre, int256 post, string memory reason) internal view {
        uint256 delta = _absDiff(pre, post);
        uint256 allowedRelative = ph.mulDivDown(_absInt(pre), maxModifyBps, 10_000);
        uint256 allowed = allowedRelative > absoluteFloorShares ? allowedRelative : absoluteFloorShares;
        require(delta <= allowed, reason);
    }
}
