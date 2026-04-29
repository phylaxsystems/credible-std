// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {ERC4626BaseAssertion} from "../ERC4626BaseAssertion.sol";

import {ISparkVaultLiquidityLike, ISparkVaultRateLike} from "./SparkVaultInterfaces.sol";

/// @title SparkVaultHelpers
/// @author Phylax Systems
/// @notice Shared Spark vault state accessors for the example assertion bundle.
abstract contract SparkVaultHelpers is ERC4626BaseAssertion {
    function _sparkChiAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISparkVaultRateLike.chi, ()), fork);
    }

    function _sparkRhoAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISparkVaultRateLike.rho, ()), fork);
    }

    function _sparkVsrAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISparkVaultRateLike.vsr, ()), fork);
    }

    function _sparkNowChiAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISparkVaultRateLike.nowChi, ()), fork);
    }

    function _sparkAssetsOutstandingAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISparkVaultLiquidityLike.assetsOutstanding, ()), fork);
    }
}
