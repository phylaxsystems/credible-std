// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AerodromeGaugeFeeFlowHelpers} from "./AerodromeGaugeFeeFlowHelpers.sol";
import {IAerodromeV1GaugeFeeFlowLike} from "./AerodromeGaugeFeeFlowInterfaces.sol";

/// @title AerodromeV1GaugeFeeFlowAssertion
/// @author Phylax Systems
/// @notice Protects Aerodrome V1 pool-fee routing through gauges.
/// - Confirms the gauge is the Voter-registered gauge for its pool.
/// - Confirms the gauge routes fee distributions only to its registered FeesVotingReward.
/// - Confirms claimed PoolFees are either parked in gauge accounting or forwarded to voters.
contract AerodromeV1GaugeFeeFlowAssertion is AerodromeGaugeFeeFlowHelpers {
    constructor(address gauge_) AerodromeGaugeFeeFlowHelpers(gauge_) {}

    /// @notice Registers V1 gauge emission notifications, the path that also claims pool fees.
    function triggers() external view override {
        registerFnCallTrigger(
            this.assertPoolFeesRouteToVotedPool.selector, IAerodromeV1GaugeFeeFlowLike.notifyRewardAmount.selector
        );
    }

    /// @notice Checks V1 pool fees claimed during gauge notification route to the voted pool reward.
    /// @dev A failure means a gauge is not linked to its Voter pool/fee-reward mapping, or
    ///      PoolFees debits did not resolve into parked gauge fees or FeesVotingReward custody.
    function assertPoolFeesRouteToVotedPool() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredGaugeIsAdopter();

        V1FeeFlowSnapshot memory pre = _v1SnapshotAt(_preCall(ctx.callStart));
        V1FeeFlowSnapshot memory post = _v1SnapshotAt(_postCall(ctx.callEnd));

        _assertVoterRoute(
            post.isPool,
            post.voterMarksGauge,
            post.voterGaugeForPool,
            post.voterPoolForGauge,
            post.voterGaugeToFees,
            post.pool,
            post.feesVotingReward,
            "AerodromeV1GaugeFees"
        );

        require(pre.sourceBalance0 >= post.sourceBalance0, "AerodromeV1GaugeFees: token0 PoolFees increased");
        require(pre.sourceBalance1 >= post.sourceBalance1, "AerodromeV1GaugeFees: token1 PoolFees increased");

        _assertFeeTokenFlow(
            pre.gaugeFees0,
            post.gaugeFees0,
            pre.sourceBalance0 - post.sourceBalance0,
            pre.rewardBalance0,
            post.rewardBalance0,
            post.gaugeBalance0,
            "AerodromeV1GaugeFees",
            "token0"
        );
        _assertFeeTokenFlow(
            pre.gaugeFees1,
            post.gaugeFees1,
            pre.sourceBalance1 - post.sourceBalance1,
            pre.rewardBalance1,
            post.rewardBalance1,
            post.gaugeBalance1,
            "AerodromeV1GaugeFees",
            "token1"
        );
    }
}
