// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IRoycoKernel
/// @author Phylax Systems
/// @notice Minimal Royco kernel surface needed by the protection suites in this folder.
/// @dev Royco tranches route deposits and redemptions through the kernel, which custody-holds
///      the senior and junior tranche assets.
interface IRoycoKernel {
    function SENIOR_TRANCHE() external view returns (address seniorTranche);
    function ST_ASSET() external view returns (address stAsset);
    function JUNIOR_TRANCHE() external view returns (address juniorTranche);
    function JT_ASSET() external view returns (address jtAsset);
}
