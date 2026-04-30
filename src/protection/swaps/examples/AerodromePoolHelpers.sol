// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {IAerodromePoolLike} from "./AerodromePoolInterfaces.sol";

/// @title AerodromePoolHelpers
/// @author Phylax Systems
/// @notice Fork-aware Aerodrome pool state helpers used by the example assertions.
abstract contract AerodromePoolHelpers is Assertion {
    address internal immutable POOL;
    address internal immutable TOKEN0;
    address internal immutable TOKEN1;
    bool internal immutable STABLE;
    uint256 internal immutable DECIMALS0;
    uint256 internal immutable DECIMALS1;

    struct PoolSnapshot {
        uint256 reserve0;
        uint256 reserve1;
        uint256 balance0;
        uint256 balance1;
        uint256 totalSupply;
        uint256 reserve0CumulativeLast;
        uint256 reserve1CumulativeLast;
        uint256 blockTimestampLast;
        uint256 observationLength;
    }

    /// @dev Accepts pool metadata explicitly so the constructor never reads from the adopter. The
    ///      Credible Layer's assertion-deploy runtime is isolated from the calling state, so a
    ///      `pool.metadata()` call in the constructor would revert with EXTCODESIZE = 0.
    constructor(address pool_, address token0_, address token1_, bool stable_, uint256 decimals0_, uint256 decimals1_) {
        POOL = pool_;
        TOKEN0 = token0_;
        TOKEN1 = token1_;
        STABLE = stable_;
        DECIMALS0 = decimals0_;
        DECIMALS1 = decimals1_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _snapshotAt(PhEvm.ForkId memory fork) internal view returns (PoolSnapshot memory snapshot) {
        snapshot.reserve0 = _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.reserve0, ()), fork);
        snapshot.reserve1 = _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.reserve1, ()), fork);
        snapshot.balance0 = _readBalanceAt(TOKEN0, POOL, fork);
        snapshot.balance1 = _readBalanceAt(TOKEN1, POOL, fork);
        snapshot.totalSupply = _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.totalSupply, ()), fork);
        snapshot.reserve0CumulativeLast =
            _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.reserve0CumulativeLast, ()), fork);
        snapshot.reserve1CumulativeLast =
            _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.reserve1CumulativeLast, ()), fork);
        snapshot.blockTimestampLast = _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.blockTimestampLast, ()), fork);
        snapshot.observationLength = _readUintAt(POOL, abi.encodeCall(IAerodromePoolLike.observationLength, ()), fork);
    }

    function _lastObservationAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (IAerodromePoolLike.Observation memory observation)
    {
        return abi.decode(
            _viewAt(POOL, abi.encodeCall(IAerodromePoolLike.lastObservation, ()), fork),
            (IAerodromePoolLike.Observation)
        );
    }

    function _poolFeesBalanceAt(address token, PhEvm.ForkId memory fork) internal view returns (uint256) {
        address poolFees = _readAddressAt(POOL, abi.encodeCall(IAerodromePoolLike.poolFees, ()), fork);
        return _readBalanceAt(token, poolFees, fork);
    }

    function _poolK(uint256 x, uint256 y) internal view returns (uint256) {
        if (!STABLE) {
            return x * y;
        }

        uint256 scaledX = (x * 1e18) / DECIMALS0;
        uint256 scaledY = (y * 1e18) / DECIMALS1;
        uint256 a = (scaledX * scaledY) / 1e18;
        uint256 b = ((scaledX * scaledX) / 1e18) + ((scaledY * scaledY) / 1e18);
        return (a * b) / 1e18;
    }
}
