// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {UniswapV3PoolHelpers} from "./UniswapV3PoolHelpers.sol";
import {IUniswapV3PoolLike} from "./UniswapV3PoolInterfaces.sol";

/// @title UniswapV3PoolAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for Uniswap v3 pools.
/// @dev Protects the pool's core AMM invariants:
///      - swaps move price only in the requested direction and never past the caller's price limit;
///      - mint/burn calls update active liquidity exactly when the position range contains the current tick;
///      - oracle observation cardinality and indexes remain internally consistent;
///      - protocol-fee accounting stays covered by pool token custody.
contract UniswapV3PoolAssertion is UniswapV3PoolHelpers {
    constructor(address pool_, address token0_, address token1_) UniswapV3PoolHelpers(pool_, token0_, token1_) {}

    /// @notice Registers Uniswap v3 pool selectors against their protection assertions.
    /// @dev The pool is the assertion adopter. Call-scoped triggers compare the exact
    ///      pre-call and post-call snapshots for the matched pool operation.
    function triggers() external view override {
        _registerLiquidityAccountingTriggers();
        _registerOracleAccountingTriggers();
        _registerProtocolFeeCustodyTriggers();

        registerFnCallTrigger(this.assertSwapPriceMovement.selector, IUniswapV3PoolLike.swap.selector);
        registerFnCallTrigger(
            this.assertCollectProtocolPreservesPoolState.selector, IUniswapV3PoolLike.collectProtocol.selector
        );
    }

    function _registerLiquidityAccountingTriggers() internal view {
        registerFnCallTrigger(this.assertActiveLiquidityAccounting.selector, IUniswapV3PoolLike.mint.selector);
        registerFnCallTrigger(this.assertActiveLiquidityAccounting.selector, IUniswapV3PoolLike.burn.selector);
    }

    function _registerOracleAccountingTriggers() internal view {
        registerFnCallTrigger(this.assertOracleStateConsistent.selector, IUniswapV3PoolLike.initialize.selector);
        registerFnCallTrigger(this.assertOracleStateConsistent.selector, IUniswapV3PoolLike.mint.selector);
        registerFnCallTrigger(this.assertOracleStateConsistent.selector, IUniswapV3PoolLike.burn.selector);
        registerFnCallTrigger(this.assertOracleStateConsistent.selector, IUniswapV3PoolLike.swap.selector);
        registerFnCallTrigger(
            this.assertOracleStateConsistent.selector, IUniswapV3PoolLike.increaseObservationCardinalityNext.selector
        );
    }

    function _registerProtocolFeeCustodyTriggers() internal view {
        registerFnCallTrigger(this.assertProtocolFeesCoveredByCustody.selector, IUniswapV3PoolLike.collect.selector);
        registerFnCallTrigger(this.assertProtocolFeesCoveredByCustody.selector, IUniswapV3PoolLike.swap.selector);
        registerFnCallTrigger(this.assertProtocolFeesCoveredByCustody.selector, IUniswapV3PoolLike.flash.selector);
        registerFnCallTrigger(
            this.assertProtocolFeesCoveredByCustody.selector, IUniswapV3PoolLike.collectProtocol.selector
        );
    }

    /// @notice A successful swap must respect direction and caller-supplied price limits.
    /// @dev For token0-to-token1 swaps `sqrtPriceX96` can only decrease; for token1-to-token0
    ///      swaps it can only increase. A failure means swap execution moved price the wrong way
    ///      or crossed the explicit limit that bounds user execution.
    function assertSwapPriceMovement() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();
        PoolSnapshot memory pre = _snapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));
        (, bool zeroForOne,, uint160 sqrtPriceLimitX96,) = _swapArgs(ph.callinputAt(ctx.callStart));

        require(post.slot0.unlocked, "UniswapV3Pool: pool left locked");
        require(post.slot0.sqrtPriceX96 >= MIN_SQRT_RATIO, "UniswapV3Pool: price below min");
        require(post.slot0.sqrtPriceX96 < MAX_SQRT_RATIO, "UniswapV3Pool: price above max");

        if (zeroForOne) {
            require(post.slot0.sqrtPriceX96 <= pre.slot0.sqrtPriceX96, "UniswapV3Pool: zeroForOne price increased");
            require(post.slot0.sqrtPriceX96 >= sqrtPriceLimitX96, "UniswapV3Pool: zeroForOne crossed limit");
        } else {
            require(post.slot0.sqrtPriceX96 >= pre.slot0.sqrtPriceX96, "UniswapV3Pool: oneForZero price decreased");
            require(post.slot0.sqrtPriceX96 <= sqrtPriceLimitX96, "UniswapV3Pool: oneForZero crossed limit");
        }
    }

    /// @notice Mint and burn must update active liquidity exactly for in-range positions.
    /// @dev Uniswap v3's global `liquidity` is only the currently active liquidity. A successful
    ///      mint/burn whose range excludes the pre-call tick must leave it unchanged; an in-range
    ///      mint/burn must add/subtract the called amount. A failure means active liquidity no
    ///      longer reflects the position range that the swap engine will use.
    function assertActiveLiquidityAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();
        PoolSnapshot memory pre = _snapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));
        int24 tickLower;
        int24 tickUpper;
        uint128 amount;

        if (ctx.selector == IUniswapV3PoolLike.mint.selector) {
            (, tickLower, tickUpper, amount,) = _mintArgs(ph.callinputAt(ctx.callStart));
            if (_inRange(pre.slot0.tick, tickLower, tickUpper)) {
                require(post.liquidity == pre.liquidity + amount, "UniswapV3Pool: mint active liquidity mismatch");
            } else {
                require(post.liquidity == pre.liquidity, "UniswapV3Pool: out-of-range mint changed liquidity");
            }
        } else {
            (tickLower, tickUpper, amount) = _burnArgs(ph.callinputAt(ctx.callStart));
            if (_inRange(pre.slot0.tick, tickLower, tickUpper)) {
                require(post.liquidity + amount == pre.liquidity, "UniswapV3Pool: burn active liquidity mismatch");
            } else {
                require(post.liquidity == pre.liquidity, "UniswapV3Pool: out-of-range burn changed liquidity");
            }
        }

        require(post.slot0.sqrtPriceX96 == pre.slot0.sqrtPriceX96, "UniswapV3Pool: liquidity op changed price");
        require(post.slot0.tick == pre.slot0.tick, "UniswapV3Pool: liquidity op changed tick");
        require(post.slot0.unlocked, "UniswapV3Pool: pool left locked");
    }

    /// @notice Oracle observation indexes and cardinality must move forward consistently.
    /// @dev Initialization, liquidity mutations, swaps, and cardinality growth can touch oracle
    ///      state. The active cardinality and next cardinality must never decrease, and initialized
    ///      pools must keep the latest observation index inside the active ring buffer.
    function assertOracleStateConsistent() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();
        Slot0Snapshot memory pre = _slot0At(_preCall(ctx.callStart));
        Slot0Snapshot memory post = _slot0At(_postCall(ctx.callEnd));

        require(post.observationCardinality >= pre.observationCardinality, "UniswapV3Pool: cardinality decreased");
        require(
            post.observationCardinalityNext >= pre.observationCardinalityNext,
            "UniswapV3Pool: cardinalityNext decreased"
        );

        if (post.sqrtPriceX96 != 0) {
            require(post.unlocked, "UniswapV3Pool: pool left locked");
            require(post.observationCardinality > 0, "UniswapV3Pool: initialized pool has no observations");
            require(
                post.observationCardinalityNext >= post.observationCardinality,
                "UniswapV3Pool: next cardinality below active"
            );
            require(
                post.observationIndex < post.observationCardinality, "UniswapV3Pool: observation index out of bounds"
            );
        }
    }

    /// @notice Accrued protocol fees must remain backed by the pool's token balances.
    /// @dev Swaps and flashes can accrue protocol fees, while collect and collectProtocol transfer
    ///      tokens out. A failure means protocol-fee accounting claims more token0 or token1 than
    ///      the pool still holds after the triggering operation.
    function assertProtocolFeesCoveredByCustody() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));

        require(post.balance0 >= post.protocolFees0, "UniswapV3Pool: token0 protocol fees uncovered");
        require(post.balance1 >= post.protocolFees1, "UniswapV3Pool: token1 protocol fees uncovered");
        require(post.slot0.unlocked, "UniswapV3Pool: pool left locked");
    }

    /// @notice Protocol-fee collection must not mutate swap-critical pool state.
    /// @dev `collectProtocol` may only reduce protocol-fee accounting and transfer the matching
    ///      token custody. A failure means owner fee collection changed price, tick, active
    ///      liquidity, oracle shape, fee growth, or increased protocol-fee liabilities.
    function assertCollectProtocolPreservesPoolState() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();
        PoolSnapshot memory pre = _snapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));

        require(post.slot0.sqrtPriceX96 == pre.slot0.sqrtPriceX96, "UniswapV3Pool: collectProtocol changed price");
        require(post.slot0.tick == pre.slot0.tick, "UniswapV3Pool: collectProtocol changed tick");
        require(
            post.slot0.observationIndex == pre.slot0.observationIndex,
            "UniswapV3Pool: collectProtocol changed observation index"
        );
        require(
            post.slot0.observationCardinality == pre.slot0.observationCardinality,
            "UniswapV3Pool: collectProtocol changed cardinality"
        );
        require(
            post.slot0.observationCardinalityNext == pre.slot0.observationCardinalityNext,
            "UniswapV3Pool: collectProtocol changed cardinalityNext"
        );
        require(post.slot0.feeProtocol == pre.slot0.feeProtocol, "UniswapV3Pool: collectProtocol changed feeProtocol");
        require(post.liquidity == pre.liquidity, "UniswapV3Pool: collectProtocol changed liquidity");
        require(
            post.feeGrowthGlobal0X128 == pre.feeGrowthGlobal0X128, "UniswapV3Pool: collectProtocol changed feeGrowth0"
        );
        require(
            post.feeGrowthGlobal1X128 == pre.feeGrowthGlobal1X128, "UniswapV3Pool: collectProtocol changed feeGrowth1"
        );
        _requireCollectProtocolCustodyMatchesFees(pre, post);
        require(post.slot0.unlocked, "UniswapV3Pool: pool left locked");
    }
}
