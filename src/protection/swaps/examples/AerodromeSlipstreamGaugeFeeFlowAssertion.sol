// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AerodromeGaugeFeeFlowHelpers} from "./AerodromeGaugeFeeFlowHelpers.sol";
import {IAerodromeSlipstreamGaugeFeeFlowLike} from "./AerodromeGaugeFeeFlowInterfaces.sol";

/// @title AerodromeSlipstreamGaugeFeeFlowAssertion
/// @author Phylax Systems
/// @notice Protects Aerodrome Slipstream gauge-fee routing for concentrated-liquidity pools.
/// - Confirms the CL gauge is the Voter-registered gauge for its pool.
/// - Confirms the CL gauge routes fee distributions only to its registered FeesVotingReward.
/// - Confirms collected `CLPool.gaugeFees()` are either parked or forwarded to voters.
contract AerodromeSlipstreamGaugeFeeFlowAssertion is AerodromeGaugeFeeFlowHelpers {
    constructor(address gauge_) AerodromeGaugeFeeFlowHelpers(gauge_) {}

    /// @notice Registers Slipstream gauge emission notifications, the path that collects CL pool fees.
    function triggers() external view override {
        registerFnCallTrigger(
            this.assertPoolFeesRouteToVotedPool.selector,
            IAerodromeSlipstreamGaugeFeeFlowLike.notifyRewardAmount.selector
        );
    }

    /// @notice Checks Slipstream pool fees collected during gauge notification route to the voted pool reward.
    /// @dev A failure means a CL gauge is not linked to its Voter pool/fee-reward mapping, or
    ///      `gaugeFees()` debits did not resolve into parked gauge fees or FeesVotingReward custody.
    function assertPoolFeesRouteToVotedPool() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredGaugeIsAdopter();

        SlipstreamFeeFlowSnapshot memory pre = _slipstreamSnapshotAt(_preCall(ctx.callStart));
        SlipstreamFeeFlowSnapshot memory post = _slipstreamSnapshotAt(_postCall(ctx.callEnd));

        _assertVoterRoute(
            post.isPool,
            post.voterMarksGauge,
            post.voterGaugeForPool,
            post.voterPoolForGauge,
            post.voterGaugeToFees,
            post.pool,
            post.feesVotingReward,
            "AerodromeSlipstreamGaugeFees"
        );

        require(pre.poolGaugeFees0 >= post.poolGaugeFees0, "AerodromeSlipstreamGaugeFees: token0 gaugeFees increased");
        require(pre.poolGaugeFees1 >= post.poolGaugeFees1, "AerodromeSlipstreamGaugeFees: token1 gaugeFees increased");

        _assertFeeTokenFlow(
            pre.gaugeFees0,
            post.gaugeFees0,
            pre.poolGaugeFees0 - post.poolGaugeFees0,
            pre.rewardBalance0,
            post.rewardBalance0,
            post.gaugeBalance0,
            "AerodromeSlipstreamGaugeFees",
            "token0"
        );
        _assertFeeTokenFlow(
            pre.gaugeFees1,
            post.gaugeFees1,
            pre.poolGaugeFees1 - post.poolGaugeFees1,
            pre.rewardBalance1,
            post.rewardBalance1,
            post.gaugeBalance1,
            "AerodromeSlipstreamGaugeFees",
            "token1"
        );
    }
}
