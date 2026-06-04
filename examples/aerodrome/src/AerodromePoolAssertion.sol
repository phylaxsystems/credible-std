// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {AerodromePoolHelpers} from "./AerodromePoolHelpers.sol";
import {IAerodromePoolLike} from "./AerodromePoolInterfaces.sol";

/// @title AerodromePoolAssertion
/// @author Phylax Systems
/// @notice Protects Aerodrome AMM pool accounting that is expensive to validate in production.
/// - Confirms post-call reserves are backed by token custody on the pool contract.
/// - Confirms swaps do not reduce the stable or volatile pool invariant across the call.
/// - Confirms `claimFees()` only debits the separated `PoolFees` custody it reports.
contract AerodromePoolAssertion is AerodromePoolHelpers {
    constructor(address pool_) AerodromePoolHelpers(pool_) {}

    /// @notice Registers Aerodrome pool mutation surfaces that affect reserves, fees, or custody.
    /// @dev Reserve backing is a transaction-wide post-state property, so it runs once at
    ///      transaction end instead of after every swap/mint/burn/skim/sync/claimFees call. K and
    ///      fee-debit checks stay bound to their specific call selectors because they need per-call
    ///      boundaries (swap-isolated invariant change, fee-claim return data).
    function triggers() external view override {
        registerTxEndTrigger(this.assertReservesBackedByBalances.selector);

        registerFnCallTrigger(this.assertSwapKNonDecreasing.selector, IAerodromePoolLike.swap.selector);
        registerFnCallTrigger(
            this.assertClaimFeesDebitsSeparatedCustody.selector, IAerodromePoolLike.claimFees.selector
        );
    }

    /// @notice Checks pool reserves remain externally backed after all pool mutations settle.
    /// @dev A failure means reserve accounting claims more token custody than the pool actually
    ///      holds at transaction end. Custody covering reserves is a transaction-wide property, so
    ///      it is evaluated once against the final (PostTx) state.
    function assertReservesBackedByBalances() external view {
        _requireConfiguredPoolIsAdopter();

        PoolSnapshot memory post = _poolSnapshotAt(_postTx());
        require(post.poolBalance0 >= post.reserve0, "AerodromePool: token0 reserves underbacked");
        require(post.poolBalance1 >= post.reserve1, "AerodromePool: token1 reserves underbacked");
    }

    /// @notice Checks a swap does not reduce the pool's core curve invariant.
    /// @dev Recomputes the same stable or volatile K shape from forked reserve snapshots. A failure
    ///      means a successful swap left LP reserves in a worse invariant state than pre-call.
    function assertSwapKNonDecreasing() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();

        PoolSnapshot memory pre = _poolSnapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _poolSnapshotAt(_postCall(ctx.callEnd));
        require(post.k >= pre.k, "AerodromePool: swap decreased K");
    }

    /// @notice Checks fee claims are paid only from separated fee custody.
    /// @dev Uses the call return values and pre/post `PoolFees` balances. A failure means
    ///      `claimFees()` reported one amount while debiting a different amount from fee custody.
    function assertClaimFeesDebitsSeparatedCustody() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredPoolIsAdopter();

        PoolSnapshot memory pre = _poolSnapshotAt(_preCall(ctx.callStart));
        PoolSnapshot memory post = _poolSnapshotAt(_postCall(ctx.callEnd));
        (uint256 claimed0, uint256 claimed1) = abi.decode(ph.callOutputAt(ctx.callStart), (uint256, uint256));

        require(pre.feeBalance0 >= post.feeBalance0, "AerodromePool: token0 fee custody increased on claim");
        require(pre.feeBalance1 >= post.feeBalance1, "AerodromePool: token1 fee custody increased on claim");
        require(pre.feeBalance0 - post.feeBalance0 == claimed0, "AerodromePool: token0 claim/custody mismatch");
        require(pre.feeBalance1 - post.feeBalance1 == claimed1, "AerodromePool: token1 claim/custody mismatch");
    }
}
