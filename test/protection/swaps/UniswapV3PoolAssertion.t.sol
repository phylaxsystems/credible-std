// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {UniswapV3PoolAssertion} from "../../../src/protection/swaps/examples/UniswapV3PoolAssertion.sol";
import {UniswapV3PoolHelpers} from "../../../src/protection/swaps/examples/UniswapV3PoolHelpers.sol";
import {IUniswapV3PoolLike} from "../../../src/protection/swaps/examples/UniswapV3PoolInterfaces.sol";

contract MockUniswapV3PoolConstructorSurface {
    address internal immutable TOKEN0;
    address internal immutable TOKEN1;

    constructor(address token0_, address token1_) {
        TOKEN0 = token0_;
        TOKEN1 = token1_;
    }

    function token0() external view returns (address) {
        return TOKEN0;
    }

    function token1() external view returns (address) {
        return TOKEN1;
    }
}

contract UniswapV3PoolAssertionHarness is UniswapV3PoolHelpers {
    constructor(address pool_) UniswapV3PoolHelpers(pool_) {}

    function triggers() external view override {}

    function requireCollectProtocolCustodyMatchesFees(
        uint256 preBalance0,
        uint256 postBalance0,
        uint256 preBalance1,
        uint256 postBalance1,
        uint128 preProtocolFees0,
        uint128 postProtocolFees0,
        uint128 preProtocolFees1,
        uint128 postProtocolFees1
    ) external pure {
        PoolSnapshot memory pre;
        pre.balance0 = preBalance0;
        pre.balance1 = preBalance1;
        pre.protocolFees0 = preProtocolFees0;
        pre.protocolFees1 = preProtocolFees1;

        PoolSnapshot memory post;
        post.balance0 = postBalance0;
        post.balance1 = postBalance1;
        post.protocolFees0 = postProtocolFees0;
        post.protocolFees1 = postProtocolFees1;

        _requireCollectProtocolCustodyMatchesFees(pre, post);
    }
}

contract UniswapV3PoolAssertionTest is Test {
    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockUniswapV3PoolConstructorSurface internal pool;
    UniswapV3PoolAssertionHarness internal harness;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        pool = new MockUniswapV3PoolConstructorSurface(address(token0), address(token1));
        harness = new UniswapV3PoolAssertionHarness(address(pool));
    }

    function testUniswapV3PoolAssertionDeploys() external {
        UniswapV3PoolAssertion assertion = new UniswapV3PoolAssertion(address(pool));

        assertTrue(address(assertion) != address(0));
    }

    function testUniswapV3PoolSelectorsMatchExpectedSignatures() external pure {
        assertEq(IUniswapV3PoolLike.mint.selector, bytes4(keccak256("mint(address,int24,int24,uint128,bytes)")));
        assertEq(IUniswapV3PoolLike.burn.selector, bytes4(keccak256("burn(int24,int24,uint128)")));
        assertEq(IUniswapV3PoolLike.swap.selector, bytes4(keccak256("swap(address,bool,int256,uint160,bytes)")));
        assertEq(
            IUniswapV3PoolLike.collectProtocol.selector, bytes4(keccak256("collectProtocol(address,uint128,uint128)"))
        );
    }

    function testCollectProtocolCustodyMatchesFeeDecrease() external view {
        harness.requireCollectProtocolCustodyMatchesFees({
            preBalance0: 1_000,
            postBalance0: 900,
            preBalance1: 2_000,
            postBalance1: 1_975,
            preProtocolFees0: 150,
            postProtocolFees0: 50,
            preProtocolFees1: 40,
            postProtocolFees1: 15
        });
    }

    function testCollectProtocolRejectsExcessToken0Drain() external {
        vm.expectRevert("UniswapV3Pool: collectProtocol token0 custody mismatch");
        harness.requireCollectProtocolCustodyMatchesFees({
            preBalance0: 1_000,
            postBalance0: 800,
            preBalance1: 2_000,
            postBalance1: 1_975,
            preProtocolFees0: 150,
            postProtocolFees0: 50,
            preProtocolFees1: 40,
            postProtocolFees1: 15
        });
    }

    function testCollectProtocolRejectsExcessToken1Drain() external {
        vm.expectRevert("UniswapV3Pool: collectProtocol token1 custody mismatch");
        harness.requireCollectProtocolCustodyMatchesFees({
            preBalance0: 1_000,
            postBalance0: 900,
            preBalance1: 2_000,
            postBalance1: 1_900,
            preProtocolFees0: 150,
            postProtocolFees0: 50,
            preProtocolFees1: 40,
            postProtocolFees1: 15
        });
    }
}
