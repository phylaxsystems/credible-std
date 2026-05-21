// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract MockAerodromeFeeFlowVoter {
    mapping(address => address) public gauges;
    mapping(address => address) public poolForGauge;
    mapping(address => address) public gaugeToFees;
    mapping(address => bool) public isGauge;

    function setRoute(address pool, address gauge, address feesVotingReward) external {
        gauges[pool] = gauge;
        poolForGauge[gauge] = pool;
        gaugeToFees[gauge] = feesVotingReward;
        isGauge[gauge] = true;
    }

    function setGaugeToFees(address gauge, address feesVotingReward) external {
        gaugeToFees[gauge] = feesVotingReward;
    }
}

contract MockAerodromeV1PoolFees {
    function pay(address token, address recipient, uint256 amount) external {
        ERC20Mock(token).transfer(recipient, amount);
    }
}

contract MockAerodromeV1FeeFlowPool {
    ERC20Mock public immutable token0;
    ERC20Mock public immutable token1;
    MockAerodromeV1PoolFees public immutable poolFees;

    uint256 public claimable0;
    uint256 public claimable1;

    constructor(ERC20Mock token0_, ERC20Mock token1_) {
        token0 = token0_;
        token1 = token1_;
        poolFees = new MockAerodromeV1PoolFees();
    }

    function seedFees(uint256 amount0, uint256 amount1) external {
        claimable0 += amount0;
        claimable1 += amount1;
        token0.mint(address(poolFees), amount0);
        token1.mint(address(poolFees), amount1);
    }

    function tokens() external view returns (address, address) {
        return (address(token0), address(token1));
    }

    function claimFees() external returns (uint256 claimed0, uint256 claimed1) {
        claimed0 = claimable0;
        claimed1 = claimable1;
        claimable0 = 0;
        claimable1 = 0;

        if (claimed0 > 0) {
            poolFees.pay(address(token0), msg.sender, claimed0);
        }
        if (claimed1 > 0) {
            poolFees.pay(address(token1), msg.sender, claimed1);
        }
    }
}

contract MockAerodromeV1FeeFlowGauge {
    enum Mode {
        Honest,
        DivertToken0
    }

    uint256 internal constant WEEK = 7 days;

    MockAerodromeV1FeeFlowPool public immutable pool;
    ERC20Mock public immutable token0;
    ERC20Mock public immutable token1;
    ERC20Mock public immutable rewardToken;
    address public immutable voter;
    address public immutable stakingToken;
    address public immutable feesVotingReward;
    bool public immutable isPool = true;

    uint256 public fees0;
    uint256 public fees1;
    Mode public mode;
    address public divertRecipient;

    constructor(
        MockAerodromeV1FeeFlowPool pool_,
        ERC20Mock rewardToken_,
        address voter_,
        address feesVotingReward_,
        address divertRecipient_
    ) {
        pool = pool_;
        token0 = pool_.token0();
        token1 = pool_.token1();
        rewardToken = rewardToken_;
        voter = voter_;
        stakingToken = address(pool_);
        feesVotingReward = feesVotingReward_;
        divertRecipient = divertRecipient_;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function seedParked(uint256 amount0, uint256 amount1) external {
        fees0 += amount0;
        fees1 += amount1;
        token0.mint(address(this), amount0);
        token1.mint(address(this), amount1);
    }

    function notifyRewardAmount(uint256 amount) external {
        _claimFees();
        if (amount > 0) {
            rewardToken.transferFrom(msg.sender, address(this), amount);
        }
    }

    function _claimFees() internal {
        (uint256 claimed0, uint256 claimed1) = pool.claimFees();
        uint256 total0 = fees0 + claimed0;
        uint256 total1 = fees1 + claimed1;

        if (total0 > WEEK) {
            fees0 = 0;
            token0.transfer(mode == Mode.DivertToken0 ? divertRecipient : feesVotingReward, total0);
        } else {
            fees0 = total0;
        }

        if (total1 > WEEK) {
            fees1 = 0;
            token1.transfer(feesVotingReward, total1);
        } else {
            fees1 = total1;
        }
    }
}

contract MockAerodromeSlipstreamFeeFlowPool {
    ERC20Mock public immutable token0;
    ERC20Mock public immutable token1;
    address public gauge;

    uint128 public gaugeFees0;
    uint128 public gaugeFees1;

    constructor(ERC20Mock token0_, ERC20Mock token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    function setGauge(address gauge_) external {
        gauge = gauge_;
    }

    function seedGaugeFees(uint128 amount0, uint128 amount1) external {
        gaugeFees0 += amount0;
        gaugeFees1 += amount1;
        token0.mint(address(this), amount0);
        token1.mint(address(this), amount1);
    }

    function gaugeFees() external view returns (uint128 token0Fees, uint128 token1Fees) {
        return (gaugeFees0, gaugeFees1);
    }

    function collectFees() external returns (uint128 amount0, uint128 amount1) {
        require(msg.sender == gauge, "MockSlipstreamPool: not gauge");

        amount0 = gaugeFees0;
        amount1 = gaugeFees1;
        if (amount0 > 1) {
            amount0--;
            gaugeFees0 = 1;
            token0.transfer(msg.sender, amount0);
        }
        if (amount1 > 1) {
            amount1--;
            gaugeFees1 = 1;
            token1.transfer(msg.sender, amount1);
        }
    }
}

contract MockAerodromeSlipstreamFeeFlowGauge {
    enum Mode {
        Honest,
        DivertToken0
    }

    uint256 internal constant WEEK = 7 days;

    MockAerodromeSlipstreamFeeFlowPool public immutable pool;
    ERC20Mock public immutable token0;
    ERC20Mock public immutable token1;
    ERC20Mock public immutable rewardToken;
    address public immutable voter;
    address public immutable feesVotingReward;
    bool public immutable isPool = true;

    uint256 public fees0;
    uint256 public fees1;
    Mode public mode;
    address public divertRecipient;

    constructor(
        MockAerodromeSlipstreamFeeFlowPool pool_,
        ERC20Mock rewardToken_,
        address voter_,
        address feesVotingReward_,
        address divertRecipient_
    ) {
        pool = pool_;
        token0 = pool_.token0();
        token1 = pool_.token1();
        rewardToken = rewardToken_;
        voter = voter_;
        feesVotingReward = feesVotingReward_;
        divertRecipient = divertRecipient_;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function seedParked(uint256 amount0, uint256 amount1) external {
        fees0 += amount0;
        fees1 += amount1;
        token0.mint(address(this), amount0);
        token1.mint(address(this), amount1);
    }

    function notifyRewardAmount(uint256 amount) external {
        _claimFees();
        if (amount > 0) {
            rewardToken.transferFrom(msg.sender, address(this), amount);
        }
    }

    function _claimFees() internal {
        (uint256 claimed0, uint256 claimed1) = pool.collectFees();
        uint256 total0 = fees0 + claimed0;
        uint256 total1 = fees1 + claimed1;

        if (total0 > WEEK) {
            fees0 = 0;
            token0.transfer(mode == Mode.DivertToken0 ? divertRecipient : feesVotingReward, total0);
        } else {
            fees0 = total0;
        }

        if (total1 > WEEK) {
            fees1 = 0;
            token1.transfer(feesVotingReward, total1);
        } else {
            fees1 = total1;
        }
    }
}
