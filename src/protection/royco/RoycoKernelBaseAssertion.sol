// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {IRoycoKernel} from "./IRoycoKernel.sol";

/// @title RoycoKernelBaseAssertion
/// @author Phylax Systems
/// @notice Base contract for Royco kernel assertions.
/// @dev Royco's tranches look vault-like to LPs, but the kernel is the actual custody point
///      for both the senior and junior tranche assets. Protection suites therefore adopt the
///      kernel and read balances from there.
abstract contract RoycoKernelBaseAssertion is Assertion {
    /// @notice Royco kernel being monitored (assertion adopter).
    address internal immutable kernel;

    /// @notice Royco market tranches controlled by the kernel.
    address internal immutable seniorTranche;
    address internal immutable juniorTranche;

    /// @notice Underlying assets custody-held by the kernel for each tranche.
    address internal immutable stAsset;
    address internal immutable jtAsset;

    constructor(address kernel_) {
        kernel = kernel_;
        seniorTranche = IRoycoKernel(kernel_).SENIOR_TRANCHE();
        stAsset = IRoycoKernel(kernel_).ST_ASSET();
        juniorTranche = IRoycoKernel(kernel_).JUNIOR_TRANCHE();
        jtAsset = IRoycoKernel(kernel_).JT_ASSET();
    }

    /// @notice Returns true when both Royco tranches share the same underlying asset.
    function _hasIdenticalAssets() internal view returns (bool) {
        return stAsset == jtAsset;
    }

    function _stAssetBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(stAsset, account, fork);
    }

    function _jtAssetBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(jtAsset, account, fork);
    }

    function _kernelStAssetBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _stAssetBalanceAt(kernel, fork);
    }

    function _kernelJtAssetBalanceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _jtAssetBalanceAt(kernel, fork);
    }
}
