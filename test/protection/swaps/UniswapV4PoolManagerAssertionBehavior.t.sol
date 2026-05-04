// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {UniswapV4PoolManagerAssertion} from
    "../../../src/protection/swaps/examples/UniswapV4PoolManagerAssertion.sol";
import {IUniswapV4PoolManagerLike} from
    "../../../src/protection/swaps/examples/UniswapV4PoolManagerInterfaces.sol";

import {MockUniswapV4PoolManager} from "../../fixtures/swaps/MockUniswapV4PoolManager.sol";

/// @title UniswapV4PoolManagerAssertionBehaviorTest
/// @notice cl.assertion-armed regression tests for the example UniswapV4PoolManagerAssertion.
/// @dev Exercises the swap-direction invariant, the active-liquidity accounting invariant, the
///      protocol-fee custody invariant, and the collectProtocolFees no-mutation invariant. The
///      mock implements only the storage-layout view surface the assertion reads (`extsload(...)`,
///      `protocolFeesAccrued(...)`) plus configurable `swap`, `modifyLiquidity`, and
///      `collectProtocolFees` mutators.
contract UniswapV4PoolManagerAssertionBehaviorTest is Test, CredibleTest {
    // sqrt(1) << 96 — neutral mid-price that lies safely between MIN_SQRT_PRICE and MAX_SQRT_PRICE.
    uint160 internal constant INITIAL_SQRT_PRICE = 79_228_162_514_264_337_593_543_950_336;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockUniswapV4PoolManager internal manager;
    IUniswapV4PoolManagerLike.PoolKey internal poolKey;

    function setUp() public {
        ERC20Mock a = new ERC20Mock();
        ERC20Mock b = new ERC20Mock();
        if (address(a) < address(b)) {
            token0 = a;
            token1 = b;
        } else {
            token0 = b;
            token1 = a;
        }

        manager = new MockUniswapV4PoolManager();
        poolKey = IUniswapV4PoolManagerLike.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        manager.setSlot0({
            key: poolKey,
            sqrtPriceX96: INITIAL_SQRT_PRICE,
            tick: 0,
            protocolFee: 0,
            lpFee: 3000
        });
        manager.setLiquidity(poolKey, 1_000_000);
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData =
            abi.encodePacked(type(UniswapV4PoolManagerAssertion).creationCode, abi.encode(address(manager), poolKey));
        cl.assertion(address(manager), createData, fnSelector);
    }

    // ------------------------------------------------------------------
    //  assertSwapPriceMovement
    // ------------------------------------------------------------------

    /// @notice An honest zeroForOne swap (price moves down) satisfies direction and limit checks.
    function testHonestZeroForOneSwapPasses() public {
        manager.setSwapMode(MockUniswapV4PoolManager.SwapMode.Honest);

        _arm(UniswapV4PoolManagerAssertion.assertSwapPriceMovement.selector);
        // Limit set just above MIN_SQRT_PRICE so the post-call price never crosses it.
        manager.swap(
            poolKey,
            IUniswapV4PoolManagerLike.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(1 ether),
                sqrtPriceLimitX96: 4_295_128_739 + 1
            }),
            ""
        );
    }

    /// @notice An honest oneForZero swap (price moves up) satisfies direction and limit checks.
    function testHonestOneForZeroSwapPasses() public {
        manager.setSwapMode(MockUniswapV4PoolManager.SwapMode.Honest);

        _arm(UniswapV4PoolManagerAssertion.assertSwapPriceMovement.selector);
        manager.swap(
            poolKey,
            IUniswapV4PoolManagerLike.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(1 ether),
                sqrtPriceLimitX96: type(uint160).max - 1
            }),
            ""
        );
    }

    /// @notice A zeroForOne swap that increases sqrtPriceX96 violates the direction invariant.
    function testWrongDirectionZeroForOneTrips() public {
        manager.setSwapMode(MockUniswapV4PoolManager.SwapMode.WrongDirection);

        _arm(UniswapV4PoolManagerAssertion.assertSwapPriceMovement.selector);
        vm.expectRevert(bytes("UniswapV4Pool: zeroForOne price increased"));
        manager.swap(
            poolKey,
            IUniswapV4PoolManagerLike.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(1 ether),
                sqrtPriceLimitX96: 4_295_128_739 + 1
            }),
            ""
        );
    }

    /// @notice A oneForZero swap that decreases sqrtPriceX96 violates the direction invariant.
    function testWrongDirectionOneForZeroTrips() public {
        manager.setSwapMode(MockUniswapV4PoolManager.SwapMode.WrongDirection);

        _arm(UniswapV4PoolManagerAssertion.assertSwapPriceMovement.selector);
        vm.expectRevert(bytes("UniswapV4Pool: oneForZero price decreased"));
        manager.swap(
            poolKey,
            IUniswapV4PoolManagerLike.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(1 ether),
                sqrtPriceLimitX96: type(uint160).max - 1
            }),
            ""
        );
    }

    /// @notice A swap on a different pool key must NOT trip the per-pool invariant.
    function testSwapOnDifferentPoolIgnored() public {
        manager.setSwapMode(MockUniswapV4PoolManager.SwapMode.WrongDirection);

        IUniswapV4PoolManagerLike.PoolKey memory otherKey = IUniswapV4PoolManagerLike.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 500, // different fee tier => different pool id
            tickSpacing: 10,
            hooks: address(0)
        });
        manager.setSlot0(otherKey, INITIAL_SQRT_PRICE, 0, 0, 500);

        _arm(UniswapV4PoolManagerAssertion.assertSwapPriceMovement.selector);
        // Wrong-direction swap on otherKey would normally trip — but the assertion filters by pool id.
        manager.swap(
            otherKey,
            IUniswapV4PoolManagerLike.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(1 ether),
                sqrtPriceLimitX96: 4_295_128_739 + 1
            }),
            ""
        );
    }

    // ------------------------------------------------------------------
    //  assertActiveLiquidityAccounting
    // ------------------------------------------------------------------

    /// @notice An in-range modifyLiquidity that adds liquidity must update active liquidity.
    function testInRangeMintPasses() public {
        _arm(UniswapV4PoolManagerAssertion.assertActiveLiquidityAccounting.selector);
        manager.modifyLiquidity(
            poolKey,
            IUniswapV4PoolManagerLike.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 500,
                salt: bytes32(0)
            }),
            ""
        );
    }

    /// @notice An in-range modifyLiquidity that removes liquidity must update active liquidity.
    function testInRangeBurnPasses() public {
        _arm(UniswapV4PoolManagerAssertion.assertActiveLiquidityAccounting.selector);
        manager.modifyLiquidity(
            poolKey,
            IUniswapV4PoolManagerLike.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: -500,
                salt: bytes32(0)
            }),
            ""
        );
    }

    /// @notice An out-of-range modifyLiquidity must leave active liquidity unchanged.
    function testOutOfRangeModifyPasses() public {
        _arm(UniswapV4PoolManagerAssertion.assertActiveLiquidityAccounting.selector);
        manager.modifyLiquidity(
            poolKey,
            IUniswapV4PoolManagerLike.ModifyLiquidityParams({
                tickLower: 120,
                tickUpper: 240,
                liquidityDelta: 500,
                salt: bytes32(0)
            }),
            ""
        );
    }

    // ------------------------------------------------------------------
    //  assertProtocolFeesCoveredByCustody
    // ------------------------------------------------------------------

    /// @notice An honest swap with fully-backed protocol fees must not trip the custody invariant.
    function testProtocolFeesCoveredOnHonestSwap() public {
        manager.setSwapMode(MockUniswapV4PoolManager.SwapMode.Honest);
        // Seed the manager with token balances that fully cover protocolFeesAccrued.
        token0.mint(address(manager), 1_000);
        token1.mint(address(manager), 1_000);
        manager.setProtocolFeesAccrued(address(token0), 100);
        manager.setProtocolFeesAccrued(address(token1), 50);

        _arm(UniswapV4PoolManagerAssertion.assertProtocolFeesCoveredByCustody.selector);
        manager.swap(
            poolKey,
            IUniswapV4PoolManagerLike.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(1 ether),
                sqrtPriceLimitX96: 4_295_128_739 + 1
            }),
            ""
        );
    }

    // ------------------------------------------------------------------
    //  assertCollectProtocolPreservesPoolState
    // ------------------------------------------------------------------

    /// @notice An honest collectProtocolFees that drains accrued currency0 fees must pass.
    function testHonestCollectProtocolFeesPasses() public {
        // Pre-seed accrual + matching custody so the manager can honor the transfer.
        token0.mint(address(manager), 200);
        token1.mint(address(manager), 100);
        manager.setProtocolFeesAccrued(address(token0), 200);
        manager.setProtocolFeesAccrued(address(token1), 100);

        _arm(UniswapV4PoolManagerAssertion.assertCollectProtocolPreservesPoolState.selector);
        manager.collectProtocolFees(address(this), address(token0), 80);
    }

    /// @notice A collectProtocolFees that drains the entire accrual (amount == 0) must pass.
    function testFullDrainCollectProtocolFeesPasses() public {
        token0.mint(address(manager), 200);
        manager.setProtocolFeesAccrued(address(token0), 200);

        _arm(UniswapV4PoolManagerAssertion.assertCollectProtocolPreservesPoolState.selector);
        manager.collectProtocolFees(address(this), address(token0), 0);
    }
}
