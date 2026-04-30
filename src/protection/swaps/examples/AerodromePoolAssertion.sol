// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AerodromePoolHelpers} from "./AerodromePoolHelpers.sol";
import {IAerodromePoolLike} from "./AerodromePoolInterfaces.sol";

/// @title AerodromePoolAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for Aerodrome AMM pools.
/// @dev Protects the pool's core swap invariants:
///      - reserves match token custody after every pool-balance mutation;
///      - swaps do not reduce the volatile or stable curve invariant;
///      - TWAP accumulators and observations remain monotonic and internally consistent;
///      - fee claims cannot touch pool liquidity, reserves, or LP supply.
contract AerodromePoolAssertion is AerodromePoolHelpers {
    constructor(address pool_, address token0_, address token1_, bool stable_, uint256 decimals0_, uint256 decimals1_)
        AerodromePoolHelpers(pool_, token0_, token1_, stable_, decimals0_, decimals1_)
    {}

    /// @notice Registers Aerodrome pool selectors against the assertion functions that protect them.
    /// @dev The pool is the assertion adopter. Each registered selector fires with a call-scoped
    ///      context so the assertions compare the exact pre-call and post-call snapshots.
    function triggers() external view override {
        _registerReserveAccountingTriggers();
        _registerOracleAccountingTriggers();
        registerFnCallTrigger(this.assertSwapKNonDecreasing.selector, IAerodromePoolLike.swap.selector);
        registerFnCallTrigger(
            this.assertClaimFeesPreservesPoolLiquidity.selector, IAerodromePoolLike.claimFees.selector
        );
    }

    function _registerReserveAccountingTriggers() internal view {
        registerFnCallTrigger(this.assertReservesMatchBalances.selector, IAerodromePoolLike.mint.selector);
        registerFnCallTrigger(this.assertReservesMatchBalances.selector, IAerodromePoolLike.burn.selector);
        registerFnCallTrigger(this.assertReservesMatchBalances.selector, IAerodromePoolLike.swap.selector);
        registerFnCallTrigger(this.assertReservesMatchBalances.selector, IAerodromePoolLike.skim.selector);
        registerFnCallTrigger(this.assertReservesMatchBalances.selector, IAerodromePoolLike.sync.selector);
    }

    function _registerOracleAccountingTriggers() internal view {
        registerFnCallTrigger(this.assertOracleStateMonotonic.selector, IAerodromePoolLike.mint.selector);
        registerFnCallTrigger(this.assertOracleStateMonotonic.selector, IAerodromePoolLike.burn.selector);
        registerFnCallTrigger(this.assertOracleStateMonotonic.selector, IAerodromePoolLike.swap.selector);
        registerFnCallTrigger(this.assertOracleStateMonotonic.selector, IAerodromePoolLike.sync.selector);
    }

    /// @notice Pool reserves must match token custody after reserve-affecting calls.
    /// @dev Aerodrome moves swap fees into `PoolFees` before `_update`, then sets reserves to
    ///      post-fee balances. A failure means LP accounting no longer matches held liquidity.
    function assertReservesMatchBalances() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));

        require(post.reserve0 == post.balance0, "AerodromePool: reserve0 != balance0");
        require(post.reserve1 == post.balance1, "AerodromePool: reserve1 != balance1");
    }

    /// @notice A successful swap must not reduce the pool curve invariant.
    /// @dev Compares reserves immediately before and after the matched `swap` call using
    ///      Aerodrome's volatile `x*y` or stable `x3y+y3x` invariant. A failure means the
    ///      swap extracted value without enough input or fees to preserve the curve.
    function assertSwapKNonDecreasing() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PoolSnapshot memory pre = _snapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _snapshotAt(_postCall(ctx.callEnd));

        require(
            _poolK(post.reserve0, post.reserve1) >= _poolK(pre.reserve0, pre.reserve1), "AerodromePool: K decreased"
        );
    }

    /// @notice TWAP cumulative reserves and observation history must move forward consistently.
    /// @dev Each `_update` path may append at most one observation. When it does, the last
    ///      observation must mirror the post-call cumulative values and timestamp. A failure
    ///      means oracle history can be stale, rewound, or detached from reserve accounting.
    function assertOracleStateMonotonic() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PoolSnapshot memory pre = _snapshotAt(_preCall(ctx.callStart));
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        PoolSnapshot memory post = _snapshotAt(afterFork);

        require(
            post.reserve0CumulativeLast >= pre.reserve0CumulativeLast, "AerodromePool: reserve0 cumulative decreased"
        );
        require(
            post.reserve1CumulativeLast >= pre.reserve1CumulativeLast, "AerodromePool: reserve1 cumulative decreased"
        );
        require(post.blockTimestampLast >= pre.blockTimestampLast, "AerodromePool: timestamp decreased");
        require(post.observationLength >= pre.observationLength, "AerodromePool: observations decreased");
        require(post.observationLength <= pre.observationLength + 1, "AerodromePool: too many observations");

        if (post.observationLength > pre.observationLength) {
            IAerodromePoolLike.Observation memory lastObservation = _lastObservationAt(afterFork);
            require(
                lastObservation.timestamp == post.blockTimestampLast, "AerodromePool: observation timestamp mismatch"
            );
            require(
                lastObservation.reserve0Cumulative == post.reserve0CumulativeLast,
                "AerodromePool: observation0 cumulative mismatch"
            );
            require(
                lastObservation.reserve1Cumulative == post.reserve1CumulativeLast,
                "AerodromePool: observation1 cumulative mismatch"
            );
        }
    }

    /// @notice Claiming accrued LP fees must not alter pool liquidity accounting.
    /// @dev `claimFees` should only settle the caller's fee entitlement out of `PoolFees`.
    ///      A failure means fee settlement changed AMM reserves, pool-held balances, or LP supply.
    function assertClaimFeesPreservesPoolLiquidity() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        PoolSnapshot memory pre = _snapshotAt(beforeFork);
        PoolSnapshot memory post = _snapshotAt(afterFork);

        require(post.reserve0 == pre.reserve0, "AerodromePool: claimFees changed reserve0");
        require(post.reserve1 == pre.reserve1, "AerodromePool: claimFees changed reserve1");
        require(post.balance0 == pre.balance0, "AerodromePool: claimFees changed balance0");
        require(post.balance1 == pre.balance1, "AerodromePool: claimFees changed balance1");
        require(post.totalSupply == pre.totalSupply, "AerodromePool: claimFees changed supply");
        require(
            _poolFeesBalanceAt(TOKEN0, afterFork) <= _poolFeesBalanceAt(TOKEN0, beforeFork),
            "AerodromePool: claimFees increased fee0 escrow"
        );
        require(
            _poolFeesBalanceAt(TOKEN1, afterFork) <= _poolFeesBalanceAt(TOKEN1, beforeFork),
            "AerodromePool: claimFees increased fee1 escrow"
        );
    }
}
