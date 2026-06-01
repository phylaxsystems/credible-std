// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {UniswapV3PoolAssertion} from "../src/UniswapV3PoolAssertion.sol";

contract MockUniswapV3Pool {
    enum SwapMode {
        Honest,
        WrongDirection
    }

    address public immutable token0;
    address public immutable token1;

    uint160 public sqrtPriceX96;
    int24 public tick;
    uint16 public observationIndex;
    uint16 public observationCardinality = 1;
    uint16 public observationCardinalityNext = 1;
    uint8 public feeProtocol;
    bool public unlocked = true;
    uint128 public liquidity;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    SwapMode public swapMode;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    function setSqrtPrice(uint160 sqrtPriceX96_) external {
        sqrtPriceX96 = sqrtPriceX96_;
    }

    function setSwapMode(SwapMode swapMode_) external {
        swapMode = swapMode_;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
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

    function protocolFees() external pure returns (uint128, uint128) {
        return (0, 0);
    }

    function swap(address, bool zeroForOne, int256, uint160, bytes calldata) external returns (int256, int256) {
        uint160 delta = sqrtPriceX96 / 100;
        bool moveDown = zeroForOne;
        if (swapMode == SwapMode.WrongDirection) {
            moveDown = !moveDown;
        }

        sqrtPriceX96 = moveDown ? sqrtPriceX96 - delta : sqrtPriceX96 + delta;
        return (0, 0);
    }
}

contract UniswapV3PoolAssertionTest is Test, CredibleTest {
    uint160 internal constant INITIAL_SQRT_PRICE = 79_228_162_514_264_337_593_543_950_336;
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockUniswapV3Pool internal pool;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        pool = new MockUniswapV3Pool(address(token0), address(token1));
        pool.setSqrtPrice(INITIAL_SQRT_PRICE);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(UniswapV3PoolAssertion).creationCode, abi.encode(address(pool), address(token0), address(token1))
        );
        cl.assertion(address(pool), createData, UniswapV3PoolAssertion.assertSwapPriceMovement.selector);
    }

    function testHonestZeroForOneSwapPasses() public {
        _arm();
        pool.swap(address(this), true, 1 ether, MIN_SQRT_RATIO + 1, "");
    }

    function testHonestOneForZeroSwapPasses() public {
        _arm();
        pool.swap(address(this), false, 1 ether, type(uint160).max - 1, "");
    }

    function testWrongDirectionZeroForOneTrips() public {
        pool.setSwapMode(MockUniswapV3Pool.SwapMode.WrongDirection);

        _arm();
        vm.expectRevert(bytes("UniswapV3Pool: zeroForOne price increased"));
        pool.swap(address(this), true, 1 ether, MIN_SQRT_RATIO + 1, "");
    }
}
