// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {UniswapV4PoolManagerAssertion} from
    "../../../src/protection/swaps/examples/UniswapV4PoolManagerAssertion.sol";
import {UniswapV4PoolManagerHelpers} from
    "../../../src/protection/swaps/examples/UniswapV4PoolManagerHelpers.sol";
import {IUniswapV4PoolManagerLike} from
    "../../../src/protection/swaps/examples/UniswapV4PoolManagerInterfaces.sol";

/// @notice Public harness exposing the helpers' internal custody invariant for direct testing.
contract UniswapV4PoolManagerAssertionHarness is UniswapV4PoolManagerHelpers {
    constructor(address manager_, IUniswapV4PoolManagerLike.PoolKey memory poolKey_)
        UniswapV4PoolManagerHelpers(manager_, poolKey_)
    {}

    function triggers() external view override {}

    function poolId() external view returns (bytes32) {
        return POOL_ID;
    }

    function poolStateBaseSlot() external view returns (bytes32) {
        return POOL_STATE_BASE_SLOT;
    }
}

contract UniswapV4PoolManagerAssertionTest is Test {
    ERC20Mock internal token0;
    ERC20Mock internal token1;
    address internal manager = makeAddr("manager");

    UniswapV4PoolManagerAssertionHarness internal harness;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        (address c0, address c1) = address(token0) < address(token1)
            ? (address(token0), address(token1))
            : (address(token1), address(token0));

        IUniswapV4PoolManagerLike.PoolKey memory key = IUniswapV4PoolManagerLike.PoolKey({
            currency0: c0,
            currency1: c1,
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        harness = new UniswapV4PoolManagerAssertionHarness(manager, key);
    }

    function testUniswapV4PoolManagerAssertionDeploys() external {
        IUniswapV4PoolManagerLike.PoolKey memory key = IUniswapV4PoolManagerLike.PoolKey({
            currency0: address(token0) < address(token1) ? address(token0) : address(token1),
            currency1: address(token0) < address(token1) ? address(token1) : address(token0),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        UniswapV4PoolManagerAssertion assertion = new UniswapV4PoolManagerAssertion(manager, key);
        assertTrue(address(assertion) != address(0));
    }

    function testUniswapV4SelectorsMatchExpectedSignatures() external pure {
        // Canonical V4 selectors. PoolKey ABI = (address,address,uint24,int24,address);
        // SwapParams ABI = (bool,int256,uint160); ModifyLiquidityParams ABI = (int24,int24,int256,bytes32).
        assertEq(
            IUniswapV4PoolManagerLike.swap.selector,
            bytes4(keccak256("swap((address,address,uint24,int24,address),(bool,int256,uint160),bytes)")),
            "swap"
        );
        assertEq(
            IUniswapV4PoolManagerLike.modifyLiquidity.selector,
            bytes4(
                keccak256(
                    "modifyLiquidity((address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)"
                )
            ),
            "modifyLiquidity"
        );
        assertEq(
            IUniswapV4PoolManagerLike.donate.selector,
            bytes4(keccak256("donate((address,address,uint24,int24,address),uint256,uint256,bytes)")),
            "donate"
        );
        assertEq(
            IUniswapV4PoolManagerLike.collectProtocolFees.selector,
            bytes4(keccak256("collectProtocolFees(address,address,uint256)")),
            "collectProtocolFees"
        );
        assertEq(
            IUniswapV4PoolManagerLike.initialize.selector,
            bytes4(keccak256("initialize((address,address,uint24,int24,address),uint160)")),
            "initialize"
        );
    }

    function testPoolIdMatchesEncodingOfPoolKey() external view {
        IUniswapV4PoolManagerLike.PoolKey memory key = IUniswapV4PoolManagerLike.PoolKey({
            currency0: address(token0) < address(token1) ? address(token0) : address(token1),
            currency1: address(token0) < address(token1) ? address(token1) : address(token0),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        assertEq(harness.poolId(), keccak256(abi.encode(key)));
    }

    function testPoolStateBaseSlotMatchesStateLibrary() external view {
        // base = keccak256(abi.encode(poolId, POOLS_SLOT)) where POOLS_SLOT = 6.
        bytes32 expected = keccak256(abi.encode(harness.poolId(), uint256(6)));
        assertEq(harness.poolStateBaseSlot(), expected);
    }

    function testRejectsMisorderedCurrencies() external {
        IUniswapV4PoolManagerLike.PoolKey memory key = IUniswapV4PoolManagerLike.PoolKey({
            currency0: address(0xFFFF),
            currency1: address(0x1111),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        vm.expectRevert(bytes("UniswapV4Pool: currencies misordered"));
        new UniswapV4PoolManagerAssertion(manager, key);
    }

    function testRejectsZeroManager() external {
        IUniswapV4PoolManagerLike.PoolKey memory key = IUniswapV4PoolManagerLike.PoolKey({
            currency0: address(0x1111),
            currency1: address(0xFFFF),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        vm.expectRevert(bytes("UniswapV4Pool: manager zero"));
        new UniswapV4PoolManagerAssertion(address(0), key);
    }
}
