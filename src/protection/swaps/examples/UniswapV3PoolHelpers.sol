// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";

import {IUniswapV3PoolLike} from "./UniswapV3PoolInterfaces.sol";

/// @title UniswapV3PoolHelpers
/// @author Phylax Systems
/// @notice Fork-aware Uniswap v3 pool state helpers used by the example assertions.
abstract contract UniswapV3PoolHelpers is Assertion {
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    address internal immutable POOL;
    address internal immutable TOKEN0;
    address internal immutable TOKEN1;

    struct Slot0Snapshot {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    struct PoolSnapshot {
        Slot0Snapshot slot0;
        uint128 liquidity;
        uint128 protocolFees0;
        uint128 protocolFees1;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint256 balance0;
        uint256 balance1;
    }

    constructor(address pool_) {
        POOL = pool_;
        TOKEN0 = IUniswapV3PoolLike(pool_).token0();
        TOKEN1 = IUniswapV3PoolLike(pool_).token1();
    }

    function _snapshotAt(PhEvm.ForkId memory fork) internal view returns (PoolSnapshot memory snapshot) {
        snapshot.slot0 = _slot0At(fork);
        snapshot.liquidity = _liquidityAt(fork);
        (snapshot.protocolFees0, snapshot.protocolFees1) = _protocolFeesAt(fork);
        snapshot.feeGrowthGlobal0X128 =
            _readUintAt(POOL, abi.encodeCall(IUniswapV3PoolLike.feeGrowthGlobal0X128, ()), fork);
        snapshot.feeGrowthGlobal1X128 =
            _readUintAt(POOL, abi.encodeCall(IUniswapV3PoolLike.feeGrowthGlobal1X128, ()), fork);
        snapshot.balance0 = _readBalanceAt(TOKEN0, POOL, fork);
        snapshot.balance1 = _readBalanceAt(TOKEN1, POOL, fork);
    }

    function _slot0At(PhEvm.ForkId memory fork) internal view returns (Slot0Snapshot memory slot0) {
        (
            slot0.sqrtPriceX96,
            slot0.tick,
            slot0.observationIndex,
            slot0.observationCardinality,
            slot0.observationCardinalityNext,
            slot0.feeProtocol,
            slot0.unlocked
        ) =
            abi.decode(
                _viewAt(POOL, abi.encodeCall(IUniswapV3PoolLike.slot0, ()), fork),
                (uint160, int24, uint16, uint16, uint16, uint8, bool)
            );
    }

    function _liquidityAt(PhEvm.ForkId memory fork) internal view returns (uint128 liquidity) {
        return abi.decode(_viewAt(POOL, abi.encodeCall(IUniswapV3PoolLike.liquidity, ()), fork), (uint128));
    }

    function _protocolFeesAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (uint128 protocolFees0, uint128 protocolFees1)
    {
        return abi.decode(_viewAt(POOL, abi.encodeCall(IUniswapV3PoolLike.protocolFees, ()), fork), (uint128, uint128));
    }

    function _mintArgs(bytes memory input)
        internal
        pure
        returns (address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes memory data)
    {
        return abi.decode(_args(input), (address, int24, int24, uint128, bytes));
    }

    function _burnArgs(bytes memory input) internal pure returns (int24 tickLower, int24 tickUpper, uint128 amount) {
        return abi.decode(_args(input), (int24, int24, uint128));
    }

    function _swapArgs(bytes memory input)
        internal
        pure
        returns (
            address recipient,
            bool zeroForOne,
            int256 amountSpecified,
            uint160 sqrtPriceLimitX96,
            bytes memory data
        )
    {
        return abi.decode(_args(input), (address, bool, int256, uint160, bytes));
    }

    function _inRange(int24 currentTick, int24 tickLower, int24 tickUpper) internal pure returns (bool) {
        return tickLower <= currentTick && currentTick < tickUpper;
    }

    function _requireConfiguredPoolIsAdopter() internal view {
        require(ph.getAssertionAdopter() == POOL, "UniswapV3Pool: configured pool is not adopter");
    }

    function _requireCollectProtocolCustodyMatchesFees(PoolSnapshot memory pre, PoolSnapshot memory post)
        internal
        pure
    {
        require(post.protocolFees0 <= pre.protocolFees0, "UniswapV3Pool: collectProtocol increased protocolFees0");
        require(post.protocolFees1 <= pre.protocolFees1, "UniswapV3Pool: collectProtocol increased protocolFees1");
        require(post.balance0 <= pre.balance0, "UniswapV3Pool: collectProtocol increased balance0");
        require(post.balance1 <= pre.balance1, "UniswapV3Pool: collectProtocol increased balance1");
        require(
            pre.balance0 - post.balance0 == pre.protocolFees0 - post.protocolFees0,
            "UniswapV3Pool: collectProtocol token0 custody mismatch"
        );
        require(
            pre.balance1 - post.balance1 == pre.protocolFees1 - post.protocolFees1,
            "UniswapV3Pool: collectProtocol token1 custody mismatch"
        );
    }

    function _args(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "UniswapV3Pool: short calldata");

        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}
