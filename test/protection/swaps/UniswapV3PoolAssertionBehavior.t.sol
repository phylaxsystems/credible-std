// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {UniswapV3PoolAssertion} from "../../../src/protection/swaps/examples/UniswapV3PoolAssertion.sol";

import {MockUniswapV3Pool} from "../../fixtures/swaps/MockUniswapV3Pool.sol";

/// @title UniswapV3PoolAssertionBehaviorTest
/// @notice cl.assertion-armed regression tests for the example UniswapV3PoolAssertion.
/// @dev Focuses on `assertSwapPriceMovement` because it exercises the most differentiated v2
///      precompile path (`ph.callinputAt(callStart)` for swap argument decoding plus `_preCall` /
///      `_postCall` snapshot reads). The mock implements only the storage view surface the
///      assertion reads — no real curve math or token transfers.
contract UniswapV3PoolAssertionBehaviorTest is Test, CredibleTest {
    // sqrt(1) << 96 — neutral mid-price that lies safely between MIN_SQRT_RATIO and MAX_SQRT_RATIO.
    uint160 internal constant INITIAL_SQRT_PRICE = 79_228_162_514_264_337_593_543_950_336;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockUniswapV3Pool internal pool;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        pool = new MockUniswapV3Pool(address(token0), address(token1));
        pool.setSlot0({
            sqrtPriceX96_: INITIAL_SQRT_PRICE,
            tick_: 0,
            observationIndex_: 0,
            observationCardinality_: 1,
            observationCardinalityNext_: 1,
            feeProtocol_: 0,
            unlocked_: true
        });
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(UniswapV3PoolAssertion).creationCode, abi.encode(address(pool), address(token0), address(token1))
        );
        cl.assertion(address(pool), createData, UniswapV3PoolAssertion.assertSwapPriceMovement.selector);
    }

    /// @notice An honest zeroForOne swap (price moves down) satisfies direction and limit checks.
    function testHonestZeroForOneSwapPasses() public {
        pool.setSwapMode(MockUniswapV3Pool.SwapMode.Honest);

        _arm();
        // Limit set far below current price so the post-call price never crosses it.
        pool.swap(address(this), true, 1 ether, 4_295_128_739 + 1, "");
    }

    /// @notice An honest oneForZero swap (price moves up) satisfies direction and limit checks.
    function testHonestOneForZeroSwapPasses() public {
        pool.setSwapMode(MockUniswapV3Pool.SwapMode.Honest);

        _arm();
        // Limit set far above current price (just below MAX_SQRT_RATIO) so we never cross it.
        pool.swap(address(this), false, 1 ether, type(uint160).max - 1, "");
    }

    /// @notice A zeroForOne swap that increases sqrtPriceX96 violates the direction invariant and
    ///         must trip `UniswapV3Pool: zeroForOne price increased`.
    function testWrongDirectionZeroForOneTrips() public {
        pool.setSwapMode(MockUniswapV3Pool.SwapMode.WrongDirection);

        _arm();
        vm.expectRevert(bytes("UniswapV3Pool: zeroForOne price increased"));
        pool.swap(address(this), true, 1 ether, 4_295_128_739 + 1, "");
    }

    /// @notice A oneForZero swap that decreases sqrtPriceX96 violates the direction invariant and
    ///         must trip `UniswapV3Pool: oneForZero price decreased`.
    function testWrongDirectionOneForZeroTrips() public {
        pool.setSwapMode(MockUniswapV3Pool.SwapMode.WrongDirection);

        _arm();
        vm.expectRevert(bytes("UniswapV3Pool: oneForZero price decreased"));
        pool.swap(address(this), false, 1 ether, type(uint160).max - 1, "");
    }
}
