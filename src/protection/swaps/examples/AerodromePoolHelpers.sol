// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {IAerodromePoolLike, IERC20BalanceReaderLike} from "./AerodromePoolInterfaces.sol";

/// @title AerodromePoolHelpers
/// @notice Fork-aware state readers and math helpers for Aerodrome pool assertions.
abstract contract AerodromePoolHelpers is Assertion {
    struct PoolSnapshot {
        uint256 dec0;
        uint256 dec1;
        uint256 reserve0;
        uint256 reserve1;
        bool stable;
        address token0;
        address token1;
        address poolFees;
        uint256 poolBalance0;
        uint256 poolBalance1;
        uint256 feeBalance0;
        uint256 feeBalance1;
        uint256 k;
    }

    address internal immutable POOL;

    constructor(address pool_) {
        POOL = pool_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "AerodromePool: fork read failed";
    }

    function _requireConfiguredPoolIsAdopter() internal view {
        require(ph.getAssertionAdopter() == POOL, "AerodromePool: configured pool is not adopter");
    }

    function _poolSnapshotAt(PhEvm.ForkId memory fork) internal view returns (PoolSnapshot memory snapshot) {
        PhEvm.StaticCallResult memory metadataResult =
            ph.staticcallAt(POOL, abi.encodeCall(IAerodromePoolLike.metadata, ()), FORK_VIEW_GAS, fork);
        require(metadataResult.ok, "AerodromePool: metadata read failed");

        (
            snapshot.dec0,
            snapshot.dec1,
            snapshot.reserve0,
            snapshot.reserve1,
            snapshot.stable,
            snapshot.token0,
            snapshot.token1
        ) = abi.decode(metadataResult.data, (uint256, uint256, uint256, uint256, bool, address, address));

        PhEvm.StaticCallResult memory feesResult =
            ph.staticcallAt(POOL, abi.encodeCall(IAerodromePoolLike.poolFees, ()), FORK_VIEW_GAS, fork);
        require(feesResult.ok, "AerodromePool: poolFees read failed");
        snapshot.poolFees = abi.decode(feesResult.data, (address));

        snapshot.poolBalance0 = _balanceAt(snapshot.token0, POOL, fork);
        snapshot.poolBalance1 = _balanceAt(snapshot.token1, POOL, fork);
        snapshot.feeBalance0 = _balanceAt(snapshot.token0, snapshot.poolFees, fork);
        snapshot.feeBalance1 = _balanceAt(snapshot.token1, snapshot.poolFees, fork);
        snapshot.k = _poolK(snapshot.reserve0, snapshot.reserve1, snapshot.dec0, snapshot.dec1, snapshot.stable);
    }

    function _balanceAt(address token, address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(token, abi.encodeCall(IERC20BalanceReaderLike.balanceOf, (account)), FORK_VIEW_GAS, fork);
        require(result.ok, "AerodromePool: balance read failed");
        return abi.decode(result.data, (uint256));
    }

    function _poolK(uint256 x, uint256 y, uint256 dec0, uint256 dec1, bool stable) internal pure returns (uint256) {
        if (!stable) {
            return x * y;
        }

        require(dec0 != 0 && dec1 != 0, "AerodromePool: zero decimals");
        uint256 scaledX = (x * 1e18) / dec0;
        uint256 scaledY = (y * 1e18) / dec1;
        uint256 a = (scaledX * scaledY) / 1e18;
        uint256 b = ((scaledX * scaledX) / 1e18) + ((scaledY * scaledY) / 1e18);
        return (a * b) / 1e18;
    }
}
