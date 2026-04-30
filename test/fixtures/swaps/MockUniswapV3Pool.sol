// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockUniswapV3Pool
/// @notice Configurable Uniswap v3 pool mock for credible-std assertion regression tests.
/// @dev Exposes the storage view surface the example UniswapV3PoolAssertion reads (`slot0`,
///      `liquidity`, `protocolFees`, `feeGrowthGlobal{0,1}X128`, `token0`, `token1`) plus a
///      configurable `swap(...)` mutator. Behaviors required by the assertion are driven by a
///      `Mode` enum: honest (move price in the requested direction), bad-direction (move price the
///      wrong way), and unlocked-violation (leave pool locked after swap).
contract MockUniswapV3Pool {
    enum SwapMode {
        Honest,
        WrongDirection
    }

    address public immutable token0;
    address public immutable token1;

    // Packed slot0 — written field-by-field for clarity. Returned via `slot0()` to match the
    // production layout the assertion's helpers expect.
    uint160 public sqrtPriceX96;
    int24 public tick;
    uint16 public observationIndex;
    uint16 public observationCardinality;
    uint16 public observationCardinalityNext;
    uint8 public feeProtocol;
    bool public unlocked;

    uint128 public liquidity;
    uint128 public protocolFees0;
    uint128 public protocolFees1;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    SwapMode public swapMode;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
        unlocked = true;
        observationCardinality = 1;
        observationCardinalityNext = 1;
    }

    // ----------------------------------------------------------------------
    //  Test setters — let the harness build deterministic state
    // ----------------------------------------------------------------------

    function setSlot0(
        uint160 sqrtPriceX96_,
        int24 tick_,
        uint16 observationIndex_,
        uint16 observationCardinality_,
        uint16 observationCardinalityNext_,
        uint8 feeProtocol_,
        bool unlocked_
    ) external {
        sqrtPriceX96 = sqrtPriceX96_;
        tick = tick_;
        observationIndex = observationIndex_;
        observationCardinality = observationCardinality_;
        observationCardinalityNext = observationCardinalityNext_;
        feeProtocol = feeProtocol_;
        unlocked = unlocked_;
    }

    function setLiquidity(uint128 liquidity_) external {
        liquidity = liquidity_;
    }

    function setProtocolFees(uint128 fees0, uint128 fees1) external {
        protocolFees0 = fees0;
        protocolFees1 = fees1;
    }

    function setFeeGrowth(uint256 g0, uint256 g1) external {
        feeGrowthGlobal0X128 = g0;
        feeGrowthGlobal1X128 = g1;
    }

    function setSwapMode(SwapMode mode_) external {
        swapMode = mode_;
    }

    // ----------------------------------------------------------------------
    //  View surface required by UniswapV3PoolHelpers
    // ----------------------------------------------------------------------

    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool)
    {
        return (
            sqrtPriceX96,
            tick,
            observationIndex,
            observationCardinality,
            observationCardinalityNext,
            feeProtocol,
            unlocked
        );
    }

    function protocolFees() external view returns (uint128, uint128) {
        return (protocolFees0, protocolFees1);
    }

    // ----------------------------------------------------------------------
    //  Mutating surface — the only function exercised by assertSwapPriceMovement
    // ----------------------------------------------------------------------

    /// @notice Stub Uniswap v3 swap that updates `sqrtPriceX96` according to the configured mode.
    /// @dev Honest: zeroForOne moves price down by `priceDelta`, oneForZero moves it up. Wrong
    ///      direction does the inverse. Caller-supplied price limit is ignored — the test fixture
    ///      uses values like type(uint160).max / MIN_SQRT_RATIO so limits never bound the move.
    function swap(
        address, /* recipient */
        bool zeroForOne,
        int256, /* amountSpecified */
        uint160, /* sqrtPriceLimitX96 */
        bytes calldata /* data */
    ) external returns (int256 amount0, int256 amount1) {
        require(unlocked, "pool locked");
        uint160 priceDelta = uint160(uint256(sqrtPriceX96) / 100); // 1% move
        bool moveDown = zeroForOne;
        if (swapMode == SwapMode.WrongDirection) {
            moveDown = !moveDown;
        }
        if (moveDown) {
            sqrtPriceX96 = sqrtPriceX96 - priceDelta;
        } else {
            sqrtPriceX96 = sqrtPriceX96 + priceDelta;
        }
        // Return values are unused by the assertion.
        amount0 = 0;
        amount1 = 0;
    }
}
