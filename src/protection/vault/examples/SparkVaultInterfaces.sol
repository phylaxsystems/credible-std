// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title ISparkVaultReferralLike
/// @author Phylax Systems
/// @notice Minimal Spark vault extension surface needed by the example assertion bundle.
/// @dev Spark adds referral overloads for deposit/mint, so the example registers their selectors
///      explicitly in addition to the standard ERC-4626 entrypoints.
interface ISparkVaultReferralLike {
    function deposit(uint256 assets, address receiver, uint16 referral) external returns (uint256 shares);
    function mint(uint256 shares, address receiver, uint16 referral) external returns (uint256 assets);
}

/// @title ISparkVaultRateLike
/// @author Phylax Systems
/// @notice Minimal Spark rate-accumulator surface needed by the example assertion bundle.
interface ISparkVaultRateLike {
    function chi() external view returns (uint192);
    function rho() external view returns (uint64);
    function vsr() external view returns (uint256);
    function nowChi() external view returns (uint256);

    function drip() external returns (uint256 nChi);
    function setVsr(uint256 newVsr) external;
}

/// @title ISparkVaultLiquidityLike
/// @author Phylax Systems
/// @notice Minimal Spark managed-liquidity surface needed by the example assertion bundle.
interface ISparkVaultLiquidityLike {
    function take(uint256 value) external;
    function assetsOutstanding() external view returns (uint256);
}
