// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {UniswapV4PoolManagerHelpers} from "./UniswapV4PoolManagerHelpers.sol";
import {IUniswapV4PoolManagerLike} from "./UniswapV4PoolManagerInterfaces.sol";

/// @title UniswapV4PoolManagerAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for a single Uniswap v4 pool sitting inside the singleton
///         PoolManager.
/// @dev Protects the pool's core AMM invariants and the manager-level custody invariants:
///      - swaps move price only in the requested direction and never past the caller's price limit;
///      - modifyLiquidity calls update active liquidity exactly when the position range contains
///        the current tick;
///      - protocol-fee accruals stay backed by the manager's currency balances;
///      - protocol-fee collection does not mutate any of the watched pool's swap-critical state.
///
/// Because the PoolManager is shared across every v4 pool, each call-scoped trigger must check
/// that the call's PoolKey matches the configured pool before evaluating the per-pool invariants.
/// Calls to other pools no-op silently.
contract UniswapV4PoolManagerAssertion is UniswapV4PoolManagerHelpers {
    constructor(address manager_, IUniswapV4PoolManagerLike.PoolKey memory poolKey_)
        UniswapV4PoolManagerHelpers(manager_, poolKey_)
    {}

    /// @notice Registers Uniswap v4 PoolManager selectors against their protection assertions.
    /// @dev The PoolManager is the assertion adopter. Call-scoped triggers compare the exact
    ///      pre-call and post-call snapshots for the matched manager operation.
    function triggers() external view override {
        registerFnCallTrigger(this.assertSwapPriceMovement.selector, IUniswapV4PoolManagerLike.swap.selector);
        registerFnCallTrigger(
            this.assertActiveLiquidityAccounting.selector, IUniswapV4PoolManagerLike.modifyLiquidity.selector
        );
        _registerProtocolFeeCustodyTriggers();
        registerFnCallTrigger(
            this.assertCollectProtocolPreservesPoolState.selector,
            IUniswapV4PoolManagerLike.collectProtocolFees.selector
        );
    }

    function _registerProtocolFeeCustodyTriggers() internal view {
        registerFnCallTrigger(
            this.assertProtocolFeesCoveredByCustody.selector, IUniswapV4PoolManagerLike.swap.selector
        );
        registerFnCallTrigger(
            this.assertProtocolFeesCoveredByCustody.selector, IUniswapV4PoolManagerLike.donate.selector
        );
        registerFnCallTrigger(
            this.assertProtocolFeesCoveredByCustody.selector, IUniswapV4PoolManagerLike.collectProtocolFees.selector
        );
    }

    /// @notice A successful swap must respect direction and caller-supplied price limits.
    /// @dev For zeroForOne swaps `sqrtPriceX96` can only decrease; for oneForZero swaps it can
    ///      only increase. The post-call price must also stay strictly inside V4's tick-range
    ///      bounds. A failure means swap execution moved price the wrong way or crossed the
    ///      explicit limit that bounds user execution.
    function assertSwapPriceMovement() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredManagerIsAdopter();
        (IUniswapV4PoolManagerLike.PoolKey memory key, IUniswapV4PoolManagerLike.SwapParams memory params,) =
            _swapArgs(ph.callinputAt(ctx.callStart));
        if (!_matchesConfiguredPool(key)) {
            return;
        }

        Slot0Snapshot memory pre = _slot0At(_preCall(ctx.callStart));
        Slot0Snapshot memory post = _slot0At(_postCall(ctx.callEnd));

        require(post.sqrtPriceX96 > MIN_SQRT_PRICE, "UniswapV4Pool: price below min");
        require(post.sqrtPriceX96 < MAX_SQRT_PRICE, "UniswapV4Pool: price above max");

        if (params.zeroForOne) {
            require(post.sqrtPriceX96 <= pre.sqrtPriceX96, "UniswapV4Pool: zeroForOne price increased");
            require(post.sqrtPriceX96 >= params.sqrtPriceLimitX96, "UniswapV4Pool: zeroForOne crossed limit");
        } else {
            require(post.sqrtPriceX96 >= pre.sqrtPriceX96, "UniswapV4Pool: oneForZero price decreased");
            require(post.sqrtPriceX96 <= params.sqrtPriceLimitX96, "UniswapV4Pool: oneForZero crossed limit");
        }
    }

    /// @notice modifyLiquidity must update active liquidity exactly for in-range positions.
    /// @dev V4's per-pool `liquidity` is only the currently active liquidity. A successful
    ///      modifyLiquidity whose range excludes the pre-call tick must leave it unchanged; an
    ///      in-range modifyLiquidity must shift it by `liquidityDelta`. A failure means active
    ///      liquidity no longer reflects the position range that the swap engine will use.
    ///      Slot0 (price + tick) must also be unchanged — modifyLiquidity is not allowed to
    ///      move the pool.
    function assertActiveLiquidityAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredManagerIsAdopter();
        (
            IUniswapV4PoolManagerLike.PoolKey memory key,
            IUniswapV4PoolManagerLike.ModifyLiquidityParams memory params,
        ) = _modifyLiquidityArgs(ph.callinputAt(ctx.callStart));
        if (!_matchesConfiguredPool(key)) {
            return;
        }

        Slot0Snapshot memory preSlot0 = _slot0At(_preCall(ctx.callStart));
        Slot0Snapshot memory postSlot0 = _slot0At(_postCall(ctx.callEnd));
        uint128 preLiquidity = _liquidityAt(_preCall(ctx.callStart));
        uint128 postLiquidity = _liquidityAt(_postCall(ctx.callEnd));

        if (_inRange(preSlot0.tick, params.tickLower, params.tickUpper)) {
            int256 expected = int256(uint256(preLiquidity)) + params.liquidityDelta;
            require(expected >= 0, "UniswapV4Pool: liquidityDelta underflows active liquidity");
            require(uint256(expected) == uint256(postLiquidity), "UniswapV4Pool: in-range liquidity mismatch");
        } else {
            require(postLiquidity == preLiquidity, "UniswapV4Pool: out-of-range liquidity changed");
        }

        require(postSlot0.sqrtPriceX96 == preSlot0.sqrtPriceX96, "UniswapV4Pool: liquidity op changed price");
        require(postSlot0.tick == preSlot0.tick, "UniswapV4Pool: liquidity op changed tick");
    }

    /// @notice Manager currency balances must keep covering accrued protocol fees.
    /// @dev Swaps and donates can accrue protocol fees, while collectProtocolFees withdraws
    ///      them. The PoolManager singleton holds tokens for every pool, but `protocolFeesAccrued`
    ///      is summed per currency across all pools, so the invariant
    ///      `manager.balanceOf(currency) >= protocolFeesAccrued(currency)` must hold globally
    ///      after every triggering operation.
    function assertProtocolFeesCoveredByCustody() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredManagerIsAdopter();
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));

        require(
            post.managerBalance0 >= post.protocolFeesAccrued0, "UniswapV4Pool: currency0 protocol fees uncovered"
        );
        require(
            post.managerBalance1 >= post.protocolFeesAccrued1, "UniswapV4Pool: currency1 protocol fees uncovered"
        );
    }

    /// @notice Protocol-fee collection must not mutate swap-critical pool state.
    /// @dev `collectProtocolFees` may only reduce `protocolFeesAccrued[currency]` and transfer
    ///      the matching token custody. A failure means owner fee collection changed the
    ///      configured pool's price, tick, fee schedule, active liquidity, or fee growth, or
    ///      the protocol-fee accounting and manager balance change disagreed for the targeted
    ///      currency. Calls collecting a currency that is not part of the watched pool only
    ///      assert the per-pool no-mutation invariant.
    function assertCollectProtocolPreservesPoolState() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredManagerIsAdopter();
        (, address currency, uint256 amount) = _collectProtocolFeesArgs(ph.callinputAt(ctx.callStart));

        PoolSnapshot memory pre = _snapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));

        require(post.slot0.sqrtPriceX96 == pre.slot0.sqrtPriceX96, "UniswapV4Pool: collectProtocol changed price");
        require(post.slot0.tick == pre.slot0.tick, "UniswapV4Pool: collectProtocol changed tick");
        require(
            post.slot0.protocolFee == pre.slot0.protocolFee, "UniswapV4Pool: collectProtocol changed protocolFee"
        );
        require(post.slot0.lpFee == pre.slot0.lpFee, "UniswapV4Pool: collectProtocol changed lpFee");
        require(post.liquidity == pre.liquidity, "UniswapV4Pool: collectProtocol changed liquidity");
        require(
            post.feeGrowthGlobal0X128 == pre.feeGrowthGlobal0X128,
            "UniswapV4Pool: collectProtocol changed feeGrowth0"
        );
        require(
            post.feeGrowthGlobal1X128 == pre.feeGrowthGlobal1X128,
            "UniswapV4Pool: collectProtocol changed feeGrowth1"
        );

        if (currency == CURRENCY0) {
            _requireCollectProtocolCustodyMatches(
                amount,
                pre.protocolFeesAccrued0,
                post.protocolFeesAccrued0,
                pre.managerBalance0,
                post.managerBalance0,
                "0"
            );
            require(
                post.protocolFeesAccrued1 == pre.protocolFeesAccrued1,
                "UniswapV4Pool: collectProtocol touched untargeted currency1 accrual"
            );
        } else if (currency == CURRENCY1) {
            _requireCollectProtocolCustodyMatches(
                amount,
                pre.protocolFeesAccrued1,
                post.protocolFeesAccrued1,
                pre.managerBalance1,
                post.managerBalance1,
                "1"
            );
            require(
                post.protocolFeesAccrued0 == pre.protocolFeesAccrued0,
                "UniswapV4Pool: collectProtocol touched untargeted currency0 accrual"
            );
        } else {
            require(
                post.protocolFeesAccrued0 == pre.protocolFeesAccrued0,
                "UniswapV4Pool: collectProtocol touched untargeted currency0 accrual"
            );
            require(
                post.protocolFeesAccrued1 == pre.protocolFeesAccrued1,
                "UniswapV4Pool: collectProtocol touched untargeted currency1 accrual"
            );
        }
    }

    /// @dev When `amount == 0`, V4 collects the full accrued amount for the currency. We treat
    ///      the actual delta as the amount taken and require the manager's balance to drop by the
    ///      same amount.
    function _requireCollectProtocolCustodyMatches(
        uint256 requestedAmount,
        uint256 preAccrued,
        uint256 postAccrued,
        uint256 preBalance,
        uint256 postBalance,
        string memory currencyTag
    ) internal pure {
        require(postAccrued <= preAccrued, _msg("UniswapV4Pool: collectProtocol increased accrued", currencyTag));
        require(postBalance <= preBalance, _msg("UniswapV4Pool: collectProtocol increased balance", currencyTag));

        uint256 accruedDelta = preAccrued - postAccrued;
        uint256 balanceDelta = preBalance - postBalance;
        require(
            accruedDelta == balanceDelta, _msg("UniswapV4Pool: collectProtocol custody mismatch", currencyTag)
        );

        if (requestedAmount != 0) {
            require(
                accruedDelta == requestedAmount,
                _msg("UniswapV4Pool: collectProtocol amount mismatch", currencyTag)
            );
        } else {
            require(postAccrued == 0, _msg("UniswapV4Pool: collectProtocol left residual accrual", currencyTag));
        }
    }

    function _msg(string memory base, string memory tag) internal pure returns (string memory) {
        return string.concat(base, " currency", tag);
    }
}
