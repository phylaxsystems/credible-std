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
