// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV4PoolManagerLike} from "../../../src/protection/swaps/examples/UniswapV4PoolManagerInterfaces.sol";

interface IERC20MockLike {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title MockUniswapV4PoolManager
/// @notice Configurable Uniswap v4 PoolManager mock for credible-std assertion regression tests.
/// @dev Layout mirrors v4-core's `PoolManager` so that `extsload(bytes32)` reads from offset 6 +
///      `keccak256(poolId, 6)` reach the right `Pool.State` slots — the same path the production
///      `StateLibrary` uses. Only the pieces the example assertion reads are populated:
///      `slot0`, `liquidity`, `feeGrowthGlobal{0,1}X128`. Behaviors required by the assertion are
///      driven by a `SwapMode` enum: honest (move price in the requested direction) and
///      wrong-direction (move price the wrong way). `modifyLiquidity` updates active liquidity
///      only when the pre-call tick is inside the position's range. `collectProtocolFees` decrements
///      `protocolFeesAccrued[currency]` and transfers tokens to the recipient.
contract MockUniswapV4PoolManager {
    enum SwapMode {
        Honest,
        WrongDirection
    }

    // ----------------------------------------------------------------------
    //  Storage layout — placed so that `_pools` lives at slot 6 (StateLibrary.POOLS_SLOT)
    // ----------------------------------------------------------------------

    address public owner;                                   // slot 0
    mapping(address => uint256) public protocolFeesAccrued; // slot 1
    address public protocolFeeController;                   // slot 2
    uint256 private _padding3;                              // slot 3
    uint256 private _padding4;                              // slot 4
    uint256 private _padding5;                              // slot 5

    struct PoolState {
        bytes32 slot0;                  // packed: sqrtPriceX96(160) | tick(24) | protocolFee(24) | lpFee(24)
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 liquidity;              // packed in low bits of its slot
    }

    mapping(bytes32 => PoolState) internal _pools;          // slot 6

    SwapMode public swapMode;

    constructor() {
        owner = msg.sender;
    }

    // ----------------------------------------------------------------------
    //  Test setters — let the harness build deterministic state
    // ----------------------------------------------------------------------

    function setSlot0(
        IUniswapV4PoolManagerLike.PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    ) external {
        bytes32 packed = bytes32(
            uint256(sqrtPriceX96)
                | (uint256(uint24(uint256(int256(tick)))) << 160)
                | (uint256(protocolFee) << 184)
                | (uint256(lpFee) << 208)
        );
        _pools[_idOf(key)].slot0 = packed;
    }

    function setLiquidity(IUniswapV4PoolManagerLike.PoolKey calldata key, uint128 liquidity) external {
        _pools[_idOf(key)].liquidity = liquidity;
    }

    function setFeeGrowth(IUniswapV4PoolManagerLike.PoolKey calldata key, uint256 g0, uint256 g1) external {
        PoolState storage pool = _pools[_idOf(key)];
        pool.feeGrowthGlobal0X128 = g0;
        pool.feeGrowthGlobal1X128 = g1;
    }

    function setProtocolFeesAccrued(address currency, uint256 amount) external {
        protocolFeesAccrued[currency] = amount;
    }

    function setSwapMode(SwapMode mode_) external {
        swapMode = mode_;
    }

    // ----------------------------------------------------------------------
    //  Pool reads
    // ----------------------------------------------------------------------

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i; i < nSlots; ++i) {
            bytes32 cur = bytes32(uint256(startSlot) + i);
            bytes32 v;
            assembly {
                v := sload(cur)
            }
            values[i] = v;
        }
    }

    // ----------------------------------------------------------------------
    //  Mutating surface — only what the example assertion exercises
    // ----------------------------------------------------------------------

    /// @notice Stub Uniswap v4 swap that updates `sqrtPriceX96` according to the configured mode.
    /// @dev Honest: zeroForOne moves price down by 1%, oneForZero moves it up by 1%. Wrong
    ///      direction does the inverse. Caller-supplied price limit is ignored — the test fixture
    ///      uses values like type(uint160).max / MIN_SQRT_PRICE+1 so limits never bound the move.
    function swap(
        IUniswapV4PoolManagerLike.PoolKey calldata key,
        IUniswapV4PoolManagerLike.SwapParams calldata params,
        bytes calldata /* hookData */
    ) external returns (int256 swapDelta) {
        PoolState storage pool = _pools[_idOf(key)];
        bytes32 packed = pool.slot0;
        uint160 sqrtPriceX96 = uint160(uint256(packed));
        uint160 priceDelta = uint160(uint256(sqrtPriceX96) / 100); // 1% move

        bool moveDown = params.zeroForOne;
        if (swapMode == SwapMode.WrongDirection) {
            moveDown = !moveDown;
        }
        if (moveDown) {
            sqrtPriceX96 = sqrtPriceX96 - priceDelta;
        } else {
            sqrtPriceX96 = sqrtPriceX96 + priceDelta;
        }

        // Replace low 160 bits of slot0 with the new price; preserve packed tick/fee bits.
        uint256 high = uint256(packed) & ~uint256(type(uint160).max);
        pool.slot0 = bytes32(high | uint256(sqrtPriceX96));
        return 0;
    }

    /// @notice Stub Uniswap v4 modifyLiquidity that adjusts active liquidity for in-range positions.
    /// @dev Returns are unused by the assertion.
    function modifyLiquidity(
        IUniswapV4PoolManagerLike.PoolKey calldata key,
        IUniswapV4PoolManagerLike.ModifyLiquidityParams calldata params,
        bytes calldata /* hookData */
    ) external returns (int256 callerDelta, int256 feesAccrued) {
        PoolState storage pool = _pools[_idOf(key)];
        int24 tick = int24(int256(uint256(pool.slot0) >> 160));
        bool inRange = params.tickLower <= tick && tick < params.tickUpper;
        if (inRange) {
            int256 newLiquidity = int256(uint256(pool.liquidity)) + params.liquidityDelta;
            require(newLiquidity >= 0, "MockUniswapV4PoolManager: liquidity underflow");
            pool.liquidity = uint128(uint256(newLiquidity));
        }
        return (0, 0);
    }

    /// @notice Stub `collectProtocolFees` that drains accrued fees and transfers tokens.
    function collectProtocolFees(address recipient, address currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        uint256 accrued = protocolFeesAccrued[currency];
        amountCollected = amount == 0 ? accrued : amount;
        require(amountCollected <= accrued, "MockUniswapV4PoolManager: insufficient accrued");
        protocolFeesAccrued[currency] = accrued - amountCollected;
        require(IERC20MockLike(currency).transfer(recipient, amountCollected), "MockUniswapV4PoolManager: transfer failed");
    }

    // ----------------------------------------------------------------------
    //  Helpers
    // ----------------------------------------------------------------------

    function poolIdOf(IUniswapV4PoolManagerLike.PoolKey calldata key) external pure returns (bytes32) {
        return _idOf(key);
    }

    function _idOf(IUniswapV4PoolManagerLike.PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }
}
