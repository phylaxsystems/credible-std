// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";
import {PhEvm} from "../../../PhEvm.sol";

import {
    IAerodromeFeeFlowErc20Like,
    IAerodromeSlipstreamGaugeFeeFlowLike,
    IAerodromeSlipstreamPoolFeeFlowLike,
    IAerodromeV1GaugeFeeFlowLike,
    IAerodromeV1PoolFeeFlowLike,
    IAerodromeVoterFeeFlowLike
} from "./AerodromeGaugeFeeFlowInterfaces.sol";

/// @title AerodromeGaugeFeeFlowHelpers
/// @notice Fork-aware readers and accounting checks for Aerodrome gauge fee routing assertions.
abstract contract AerodromeGaugeFeeFlowHelpers is Assertion {
    uint256 internal constant WEEK = 7 days;

    struct V1FeeFlowSnapshot {
        address pool;
        address poolFees;
        address feesVotingReward;
        address voter;
        address token0;
        address token1;
        bool isPool;
        bool voterMarksGauge;
        address voterGaugeForPool;
        address voterPoolForGauge;
        address voterGaugeToFees;
        uint256 sourceBalance0;
        uint256 sourceBalance1;
        uint256 gaugeBalance0;
        uint256 gaugeBalance1;
        uint256 rewardBalance0;
        uint256 rewardBalance1;
        uint256 gaugeFees0;
        uint256 gaugeFees1;
    }

    struct SlipstreamFeeFlowSnapshot {
        address pool;
        address feesVotingReward;
        address voter;
        address token0;
        address token1;
        bool isPool;
        bool voterMarksGauge;
        address voterGaugeForPool;
        address voterPoolForGauge;
        address voterGaugeToFees;
        uint256 poolGaugeFees0;
        uint256 poolGaugeFees1;
        uint256 gaugeBalance0;
        uint256 gaugeBalance1;
        uint256 rewardBalance0;
        uint256 rewardBalance1;
        uint256 gaugeFees0;
        uint256 gaugeFees1;
    }

    address internal immutable GAUGE;

    constructor(address gauge_) {
        GAUGE = gauge_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "AerodromeGaugeFees: fork read failed";
    }

    function _requireConfiguredGaugeIsAdopter() internal view {
        require(ph.getAssertionAdopter() == GAUGE, "AerodromeGaugeFees: configured gauge is not adopter");
    }

    function _v1SnapshotAt(PhEvm.ForkId memory fork) internal view returns (V1FeeFlowSnapshot memory snapshot) {
        snapshot.pool = _readAddressAt(GAUGE, abi.encodeCall(IAerodromeV1GaugeFeeFlowLike.stakingToken, ()), fork);
        snapshot.feesVotingReward =
            _readAddressAt(GAUGE, abi.encodeCall(IAerodromeV1GaugeFeeFlowLike.feesVotingReward, ()), fork);
        snapshot.voter = _readAddressAt(GAUGE, abi.encodeCall(IAerodromeV1GaugeFeeFlowLike.voter, ()), fork);
        snapshot.isPool = _readBoolAt(GAUGE, abi.encodeCall(IAerodromeV1GaugeFeeFlowLike.isPool, ()), fork);
        snapshot.gaugeFees0 = _readUintAt(GAUGE, abi.encodeCall(IAerodromeV1GaugeFeeFlowLike.fees0, ()), fork);
        snapshot.gaugeFees1 = _readUintAt(GAUGE, abi.encodeCall(IAerodromeV1GaugeFeeFlowLike.fees1, ()), fork);

        snapshot.poolFees =
            _readAddressAt(snapshot.pool, abi.encodeCall(IAerodromeV1PoolFeeFlowLike.poolFees, ()), fork);
        (snapshot.token0, snapshot.token1) = abi.decode(
            _viewAt(snapshot.pool, abi.encodeCall(IAerodromeV1PoolFeeFlowLike.tokens, ()), fork), (address, address)
        );

        _readVoterRoute(snapshot.voter, snapshot.pool, snapshot, fork);
        _readV1Balances(snapshot, fork);
    }

    function _slipstreamSnapshotAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (SlipstreamFeeFlowSnapshot memory snapshot)
    {
        snapshot.pool = _readAddressAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.pool, ()), fork);
        snapshot.feesVotingReward =
            _readAddressAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.feesVotingReward, ()), fork);
        snapshot.voter = _readAddressAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.voter, ()), fork);
        snapshot.isPool = _readBoolAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.isPool, ()), fork);
        snapshot.token0 = _readAddressAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.token0, ()), fork);
        snapshot.token1 = _readAddressAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.token1, ()), fork);
        snapshot.gaugeFees0 = _readUintAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.fees0, ()), fork);
        snapshot.gaugeFees1 = _readUintAt(GAUGE, abi.encodeCall(IAerodromeSlipstreamGaugeFeeFlowLike.fees1, ()), fork);
        (snapshot.poolGaugeFees0, snapshot.poolGaugeFees1) = abi.decode(
            _viewAt(snapshot.pool, abi.encodeCall(IAerodromeSlipstreamPoolFeeFlowLike.gaugeFees, ()), fork),
            (uint128, uint128)
        );

        _readVoterRoute(snapshot.voter, snapshot.pool, snapshot, fork);
        _readSlipstreamBalances(snapshot, fork);
    }

    function _readVoterRoute(address voter, address pool, V1FeeFlowSnapshot memory snapshot, PhEvm.ForkId memory fork)
        private
        view
    {
        snapshot.voterMarksGauge = _readBoolAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.isGauge, (GAUGE)), fork);
        snapshot.voterGaugeForPool =
            _readAddressAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.gauges, (pool)), fork);
        snapshot.voterPoolForGauge =
            _readAddressAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.poolForGauge, (GAUGE)), fork);
        snapshot.voterGaugeToFees =
            _readAddressAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.gaugeToFees, (GAUGE)), fork);
    }

    function _readVoterRoute(
        address voter,
        address pool,
        SlipstreamFeeFlowSnapshot memory snapshot,
        PhEvm.ForkId memory fork
    ) private view {
        snapshot.voterMarksGauge = _readBoolAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.isGauge, (GAUGE)), fork);
        snapshot.voterGaugeForPool =
            _readAddressAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.gauges, (pool)), fork);
        snapshot.voterPoolForGauge =
            _readAddressAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.poolForGauge, (GAUGE)), fork);
        snapshot.voterGaugeToFees =
            _readAddressAt(voter, abi.encodeCall(IAerodromeVoterFeeFlowLike.gaugeToFees, (GAUGE)), fork);
    }

    function _readV1Balances(V1FeeFlowSnapshot memory snapshot, PhEvm.ForkId memory fork) private view {
        snapshot.sourceBalance0 = _balanceAt(snapshot.token0, snapshot.poolFees, fork);
        snapshot.sourceBalance1 = _balanceAt(snapshot.token1, snapshot.poolFees, fork);
        snapshot.gaugeBalance0 = _balanceAt(snapshot.token0, GAUGE, fork);
        snapshot.gaugeBalance1 = _balanceAt(snapshot.token1, GAUGE, fork);
        snapshot.rewardBalance0 = _balanceAt(snapshot.token0, snapshot.feesVotingReward, fork);
        snapshot.rewardBalance1 = _balanceAt(snapshot.token1, snapshot.feesVotingReward, fork);
    }

    function _readSlipstreamBalances(SlipstreamFeeFlowSnapshot memory snapshot, PhEvm.ForkId memory fork) private view {
        snapshot.gaugeBalance0 = _balanceAt(snapshot.token0, GAUGE, fork);
        snapshot.gaugeBalance1 = _balanceAt(snapshot.token1, GAUGE, fork);
        snapshot.rewardBalance0 = _balanceAt(snapshot.token0, snapshot.feesVotingReward, fork);
        snapshot.rewardBalance1 = _balanceAt(snapshot.token1, snapshot.feesVotingReward, fork);
    }

    function _balanceAt(address token, address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(token, abi.encodeCall(IAerodromeFeeFlowErc20Like.balanceOf, (account)), fork);
    }

    function _assertVoterRoute(
        bool isPool,
        bool voterMarksGauge,
        address voterGaugeForPool,
        address voterPoolForGauge,
        address voterGaugeToFees,
        address pool,
        address feesVotingReward,
        string memory prefix
    ) internal view {
        require(isPool, string.concat(prefix, ": gauge is not pool gauge"));
        require(voterMarksGauge, string.concat(prefix, ": voter does not mark gauge"));
        require(voterGaugeForPool == GAUGE, string.concat(prefix, ": pool not mapped to gauge"));
        require(voterPoolForGauge == pool, string.concat(prefix, ": gauge not mapped to pool"));
        require(voterGaugeToFees == feesVotingReward, string.concat(prefix, ": gauge not mapped to fee reward"));
    }

    function _assertFeeTokenFlow(
        uint256 preParked,
        uint256 postParked,
        uint256 claimed,
        uint256 preRewardBalance,
        uint256 postRewardBalance,
        uint256 postGaugeBalance,
        string memory prefix,
        string memory tokenLabel
    ) internal pure {
        uint256 accrued = preParked + claimed;
        uint256 expectedParked = accrued > WEEK ? 0 : accrued;
        uint256 expectedRewardDelta = accrued > WEEK ? accrued : 0;

        require(postRewardBalance >= preRewardBalance, string.concat(prefix, ": ", tokenLabel, " reward decreased"));
        require(
            postRewardBalance - preRewardBalance == expectedRewardDelta,
            string.concat(prefix, ": ", tokenLabel, " reward amount mismatch")
        );
        require(postParked == expectedParked, string.concat(prefix, ": ", tokenLabel, " parked amount mismatch"));
        require(postGaugeBalance >= postParked, string.concat(prefix, ": ", tokenLabel, " parked fees underbacked"));
    }
}
