// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal ERC20 balance reader used for fork-aware fee custody checks.
interface IAerodromeFeeFlowErc20Like {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal Voter surface shared by Aerodrome V1 and Slipstream gauge assertions.
interface IAerodromeVoterFeeFlowLike {
    function gauges(address pool) external view returns (address);
    function poolForGauge(address gauge) external view returns (address);
    function gaugeToFees(address gauge) external view returns (address);
    function isGauge(address gauge) external view returns (bool);
}

/// @notice Minimal Aerodrome V1 gauge surface used by fee-flow assertions.
interface IAerodromeV1GaugeFeeFlowLike {
    function notifyRewardAmount(uint256 amount) external;
    function stakingToken() external view returns (address);
    function feesVotingReward() external view returns (address);
    function voter() external view returns (address);
    function isPool() external view returns (bool);
    function fees0() external view returns (uint256);
    function fees1() external view returns (uint256);
}

/// @notice Minimal Aerodrome V1 pool surface used by fee-flow assertions.
interface IAerodromeV1PoolFeeFlowLike {
    function poolFees() external view returns (address);
    function tokens() external view returns (address token0, address token1);
}

/// @notice Minimal Slipstream gauge surface used by fee-flow assertions.
interface IAerodromeSlipstreamGaugeFeeFlowLike {
    function notifyRewardAmount(uint256 amount) external;
    function pool() external view returns (address);
    function feesVotingReward() external view returns (address);
    function voter() external view returns (address);
    function isPool() external view returns (bool);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fees0() external view returns (uint256);
    function fees1() external view returns (uint256);
}

/// @notice Minimal Slipstream pool surface used by fee-flow assertions.
interface IAerodromeSlipstreamPoolFeeFlowLike {
    function gaugeFees() external view returns (uint128 token0, uint128 token1);
}
