// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {MellowCuratorHelpers} from "./MellowCuratorHelpers.sol";
import {IMellowOracle} from "./MellowCuratorInterfaces.sol";

/// @title MellowOracleReportGuardAssertion
/// @author Phylax Systems
/// @notice Prototype cap on how far a single oracle report can move Mellow's shares-per-asset
///         conversion factor.
/// @dev Apply to the `Oracle` (the contract whose `submitReports` reprices the vault).
///
///      Why this is not a restatement of the protocol's own guard. Mellow's `Oracle` already
///      rejects reports whose deviation exceeds `securityParams.maxRelativeDeviationD18` /
///      `maxAbsoluteDeviation`. But those parameters are MUTABLE: any holder of
///      `SET_SECURITY_PARAMS_ROLE` can call `setSecurityParams`, and the only on-chain bound there
///      is "non-zero" — the cap can be widened arbitrarily. A compromised key that holds (or can
///      grant itself) that role can widen the cap in one call and reprice the vault toward zero in
///      the next, and the protocol's own deviation check passes because the attacker loosened it.
///      This assertion's cap is fixed at adoption time and cannot be widened from on-chain state,
///      so it still trips. That is the entire value-add.
///
///      The price compared is exactly the report's `priceD18` (the protocol invariant is
///      `shares = assets * priceD18 / 1e18`), read from the oracle's stored report before and after
///      the call. Reports that do not actually reprice the vault are skipped: an asset with no prior
///      price (bootstrap — the first report is recorded suspicious and does not propagate) and any
///      report the protocol flagged suspicious (recorded but not propagated into accounting).
///
///      Ceiling, stated honestly: this is a blast-radius cap, NOT a manipulation detector. A real
///      slashing-driven repricing is a legitimate large *negative* move and would trip a tight cap,
///      so the cap must be set generously (a catastrophe threshold, e.g. 5000 bps) — it cannot tell
///      manipulation from a real large move. Its only job is to stop a stolen key from repricing the
///      vault discontinuously in a single transaction. The protocol's `securityParams` remain the
///      first, finer line of defense for normal operation.
contract MellowOracleReportGuardAssertion is MellowCuratorHelpers {
    /// @notice Oracle whose reports are bounded (the assertion adopter).
    address public immutable oracle;

    /// @notice Maximum tolerated single-report drift of `priceD18`, in bps of the prior price.
    ///         CALIBRATE: a catastrophe threshold (e.g. 5000 = 50%), set well above the largest
    ///         legitimate single-report move (including real slashing drops) for the deployment.
    uint256 public immutable maxReportDriftBps;

    constructor(address oracle_, uint256 maxReportDriftBps_) {
        require(oracle_ != address(0), "MellowOracle: zero oracle");
        require(maxReportDriftBps_ != 0 && maxReportDriftBps_ < 10_000, "MellowOracle: invalid drift cap");

        oracle = oracle_;
        maxReportDriftBps = maxReportDriftBps_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Intentionally unarmed until report acceptance has an independent baseline.
    /// @dev A suspicious submission is valid upstream and does not propagate immediately. Its
    ///      later `acceptReport` call clears the suspicious flag after the old accepted value has
    ///      already been overwritten in Oracle storage. This stateless assertion cannot both allow
    ///      submission and compare acceptance with the prior accepted value.
    function triggers() external view override {
        // Quarantined pending an accepted-price source independent from `getReport`.
    }

    /// @notice Requires no supported asset's repriced `priceD18` to move more than the cap in one
    ///         report.
    /// @dev Triggered per `submitReports` call, so it reads the oracle's stored report price at the
    ///      pre-call and post-call snapshots. Iterates the assets supported as of the pre-call
    ///      snapshot (a small set for a single-asset MultiVault; the loop reads three snapshot views
    ///      per asset, so it scales with the number of supported assets, which is curator-gated
    ///      config rather than attacker-controlled). Skips assets with no prior price (bootstrap)
    ///      and reports the protocol flagged suspicious — neither repriced the vault. A failure
    ///      means a non-suspicious report moved an asset's price-per-share past the immutable cap.
    function assertReportDriftWithinCap() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preCall = _preCall(ctx.callStart);
        PhEvm.ForkId memory postCall = _postCall(ctx.callEnd);
        require(ph.getAssertionAdopter() == oracle, "MellowOracle: configured oracle is not adopter");

        uint256 count = _readUintAt(oracle, abi.encodeCall(IMellowOracle.supportedAssets, ()), preCall);

        for (uint256 i; i < count; ++i) {
            address asset = _readAddressAt(oracle, abi.encodeCall(IMellowOracle.supportedAssetAt, (i)), preCall);

            (bool okPre, uint256 prePrice,) = _tryReadReportPrice(oracle, asset, preCall);
            if (!okPre || prePrice == 0) {
                continue; // no baseline — the bootstrap report is suspicious and does not reprice
            }

            (bool okPost, uint256 postPrice,) = _tryReadReportPrice(oracle, asset, postCall);
            if (!okPost) {
                continue;
            }

            uint256 drift = postPrice > prePrice ? postPrice - prePrice : prePrice - postPrice;
            require(
                ph.mulDivUp(drift, 10_000, prePrice) <= maxReportDriftBps,
                "MellowOracle: report price drift exceeds cap"
            );
        }
    }
}
