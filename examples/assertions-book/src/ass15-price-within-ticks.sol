// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Simplified Uniswap V3 Pool
 * @notice This contract mimics a simplified Uniswap V3 pool for testing the PriceWithinTicks assertion
 * @dev Contains simplified storage and methods to simulate Uniswap V3 pool behavior
 */
contract UniswapV3Pool {
    // Storage for slot0 data
    uint160 private _sqrtPriceX96;
    int24 private _tick;
    uint16 private _observationIndex;
    uint16 private _observationCardinality;
    uint16 private _observationCardinalityNext;
    uint8 private _feeProtocol;
    bool private _unlocked;

    // Tick spacing - determines which ticks can be initialized
    int24 private _tickSpacing;

    // Uniswap V3 tick bounds
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;

    /**
     * @notice Constructor that initializes the pool with default values
     * @param initialTick The initial tick value
     * @param initialTickSpacing The initial tick spacing value
     */
    constructor(int24 initialTick, int24 initialTickSpacing) {
        require(initialTickSpacing > 0, "TS");
        require(initialTick % initialTickSpacing == 0, "TNA");
        require(initialTick >= MIN_TICK && initialTick <= MAX_TICK, "TOR");

        _tick = initialTick;
        _tickSpacing = initialTickSpacing;
        _sqrtPriceX96 = 2 ** 96; // Default price of 1.0
        _unlocked = true;
    }

    /**
     * @notice Returns the current slot0 data
     * @return sqrtPriceX96 The current sqrt price as a Q64.96
     * @return tick The current tick
     * @return observationIndex The current observation index
     * @return observationCardinality The current observation cardinality
     * @return observationCardinalityNext The next observation cardinality
     * @return feeProtocol The current fee protocol
     * @return unlocked The current unlocked status
     */
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (
            _sqrtPriceX96,
            _tick,
            _observationIndex,
            _observationCardinality,
            _observationCardinalityNext,
            _feeProtocol,
            _unlocked
        );
    }

    /**
     * @notice Returns the current tick spacing
     * @return The current tick spacing
     */
    function tickSpacing() external view returns (int24) {
        return _tickSpacing;
    }

    /**
     * @notice Simulates a swap by setting a new tick value
     * @param newTick The new tick value to set
     */
    function setTick(int24 newTick) external {
        _tick = newTick;
    }

    /**
     * @notice Sets a new tick spacing value
     * @param newTickSpacing The new tick spacing to set
     */
    function setTickSpacing(int24 newTickSpacing) external {
        require(newTickSpacing > 0, "TS");
        _tickSpacing = newTickSpacing;
    }
}
