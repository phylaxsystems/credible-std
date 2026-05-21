// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    AerodromeSlipstreamGaugeFeeFlowAssertion
} from "../../../src/protection/swaps/examples/AerodromeSlipstreamGaugeFeeFlowAssertion.sol";
import {
    AerodromeV1GaugeFeeFlowAssertion
} from "../../../src/protection/swaps/examples/AerodromeV1GaugeFeeFlowAssertion.sol";

import {
    MockAerodromeFeeFlowVoter,
    MockAerodromeSlipstreamFeeFlowGauge,
    MockAerodromeSlipstreamFeeFlowPool,
    MockAerodromeV1FeeFlowGauge,
    MockAerodromeV1FeeFlowPool
} from "../../fixtures/swaps/MockAerodromeGaugeFeeFlow.sol";

/// @title AerodromeGaugeFeeFlowAssertionTest
/// @notice cl.assertion-armed tests for V1 and Slipstream gauge fee routing checks.
contract AerodromeGaugeFeeFlowAssertionTest is Test, CredibleTest {
    uint256 internal constant WEEK = 7 days;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    ERC20Mock internal rewardToken;
    address internal feeReward = address(0xFEE);
    address internal wrongFeeReward = address(0xBADFEE);
    address internal divertRecipient = address(0xD1CE);

    MockAerodromeFeeFlowVoter internal voter;
    MockAerodromeV1FeeFlowPool internal v1Pool;
    MockAerodromeV1FeeFlowGauge internal v1Gauge;
    MockAerodromeSlipstreamFeeFlowPool internal slipstreamPool;
    MockAerodromeSlipstreamFeeFlowGauge internal slipstreamGauge;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        rewardToken = new ERC20Mock();
        voter = new MockAerodromeFeeFlowVoter();

        v1Pool = new MockAerodromeV1FeeFlowPool(token0, token1);
        v1Gauge = new MockAerodromeV1FeeFlowGauge(v1Pool, rewardToken, address(voter), feeReward, divertRecipient);
        voter.setRoute(address(v1Pool), address(v1Gauge), feeReward);

        slipstreamPool = new MockAerodromeSlipstreamFeeFlowPool(token0, token1);
        slipstreamGauge = new MockAerodromeSlipstreamFeeFlowGauge(
            slipstreamPool, rewardToken, address(voter), feeReward, divertRecipient
        );
        slipstreamPool.setGauge(address(slipstreamGauge));
        voter.setRoute(address(slipstreamPool), address(slipstreamGauge), feeReward);

        rewardToken.mint(address(this), 1_000_000 ether);
        rewardToken.approve(address(v1Gauge), type(uint256).max);
        rewardToken.approve(address(slipstreamGauge), type(uint256).max);
    }

    function _armV1() internal {
        bytes memory createData =
            abi.encodePacked(type(AerodromeV1GaugeFeeFlowAssertion).creationCode, abi.encode(address(v1Gauge)));
        cl.assertion(
            address(v1Gauge), createData, AerodromeV1GaugeFeeFlowAssertion.assertPoolFeesRouteToVotedPool.selector
        );
    }

    function _armSlipstream() internal {
        bytes memory createData = abi.encodePacked(
            type(AerodromeSlipstreamGaugeFeeFlowAssertion).creationCode, abi.encode(address(slipstreamGauge))
        );
        cl.assertion(
            address(slipstreamGauge),
            createData,
            AerodromeSlipstreamGaugeFeeFlowAssertion.assertPoolFeesRouteToVotedPool.selector
        );
    }

    /// @notice V1 pool fees pass when claimed PoolFees custody is forwarded to the gauge's FeesVotingReward.
    function testV1FeesRouteToFeeVotingRewardPasses() public {
        v1Gauge.seedParked(WEEK, WEEK);
        v1Pool.seedFees(10, 20);

        _armV1();
        v1Gauge.notifyRewardAmount(1 ether);
    }

    /// @notice V1 trips when claimed pool fees are diverted away from the voted pool fee reward.
    function testV1DivertedFeesTrip() public {
        v1Gauge.seedParked(WEEK, WEEK);
        v1Pool.seedFees(10, 20);
        v1Gauge.setMode(MockAerodromeV1FeeFlowGauge.Mode.DivertToken0);

        _armV1();
        vm.expectRevert(bytes("AerodromeV1GaugeFees: token0 reward amount mismatch"));
        v1Gauge.notifyRewardAmount(1 ether);
    }

    /// @notice V1 trips when Voter no longer maps the gauge to its configured FeesVotingReward.
    function testV1WrongVoterFeeRewardTrips() public {
        v1Pool.seedFees(10, 20);
        voter.setGaugeToFees(address(v1Gauge), wrongFeeReward);

        _armV1();
        vm.expectRevert(bytes("AerodromeV1GaugeFees: gauge not mapped to fee reward"));
        v1Gauge.notifyRewardAmount(1 ether);
    }

    /// @notice Slipstream pool fees pass when collected CL gauge fees are forwarded to FeesVotingReward.
    function testSlipstreamFeesRouteToFeeVotingRewardPasses() public {
        slipstreamGauge.seedParked(WEEK, WEEK);
        slipstreamPool.seedGaugeFees(11, 21);

        _armSlipstream();
        slipstreamGauge.notifyRewardAmount(1 ether);
    }

    /// @notice Slipstream trips when collected CL pool fees are diverted away from the voted pool fee reward.
    function testSlipstreamDivertedFeesTrip() public {
        slipstreamGauge.seedParked(WEEK, WEEK);
        slipstreamPool.seedGaugeFees(11, 21);
        slipstreamGauge.setMode(MockAerodromeSlipstreamFeeFlowGauge.Mode.DivertToken0);

        _armSlipstream();
        vm.expectRevert(bytes("AerodromeSlipstreamGaugeFees: token0 reward amount mismatch"));
        slipstreamGauge.notifyRewardAmount(1 ether);
    }

    /// @notice Slipstream trips when Voter no longer maps the CL gauge to its configured FeesVotingReward.
    function testSlipstreamWrongVoterFeeRewardTrips() public {
        slipstreamPool.seedGaugeFees(11, 21);
        voter.setGaugeToFees(address(slipstreamGauge), wrongFeeReward);

        _armSlipstream();
        vm.expectRevert(bytes("AerodromeSlipstreamGaugeFees: gauge not mapped to fee reward"));
        slipstreamGauge.notifyRewardAmount(1 ether);
    }
}
