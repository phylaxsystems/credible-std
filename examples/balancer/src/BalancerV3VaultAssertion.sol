// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {BalancerV3VaultHelpers} from "./BalancerV3VaultHelpers.sol";
import {IBalancerV3VaultLike} from "./BalancerV3VaultInterfaces.sol";

/// @title BalancerV3VaultAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for one Balancer V3 pool inside the singleton Vault.
/// @dev Balancer V3 concentrates all custody and accounting in the Vault and delegates swap math
///      to the pool contract, trusting `onSwap`'s answer. This bundle re-checks the external facts
///      that no Vault `require` expresses:
///      - a swap may never decrease the pool's own invariant or mint/burn BPT;
///      - the Vault's real token custody must always cover its internal reserves, and reserves must
///        cover the watched pool's recorded balances plus accrued aggregate protocol fees;
///      - rate-provider rates feeding the pool's live balances may not jump within one transaction.
///
///      Because the Vault is shared across every V3 pool, the call-scoped swap check filters on the
///      watched pool and silently ignores swaps in other pools. Tx-end checks read only the watched
///      pool's accounting, so unrelated pool activity cannot produce false positives.
contract BalancerV3VaultAssertion is BalancerV3VaultHelpers {
    constructor(address vault_, address pool_, uint256 invariantDustToleranceBps_, uint256 rateDriftToleranceBps_)
        BalancerV3VaultHelpers(vault_, pool_, invariantDustToleranceBps_, rateDriftToleranceBps_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers Vault selectors against their protection assertions.
    /// @dev The Vault is the assertion adopter. The swap check is call-scoped so it compares the
    ///      exact pre-call and post-call snapshots of the matched swap; the custody and rate checks
    ///      are transaction-wide envelopes because add/remove liquidity, buffer operations, and fee
    ///      collection all move the same accounting.
    function triggers() external view override {
        registerFnCallTrigger(this.assertSwapPreservesPoolInvariant.selector, IBalancerV3VaultLike.swap.selector);
        registerTxEndTrigger(this.assertVaultCustodyCoversPoolAccounting.selector);
        registerTxEndTrigger(this.assertTokenRatesWithinDriftBound.selector);
    }

    /// @notice A swap must grow (or at worst preserve) the pool invariant and touch nothing else.
    /// @dev The Vault takes `onSwap`'s output on trust: no `require` recomputes the curve. This
    ///      check recomputes the pool's invariant from live balances through the pool's own math at
    ///      the pre-call and post-call forks. With any nonzero swap fee the invariant must grow, so
    ///      it may never drop by more than the configured rounding dust. BPT supply must be frozen
    ///      across a swap, and live balances must move in the swap's direction (tokenIn in,
    ///      tokenOut out); rates are fixed within one swap call, so live-balance direction mirrors
    ///      raw custody direction, and in-tx rate movement is covered by the drift assertion.
    ///      A failure means broken or manipulated pool math let value leak out of the pool.
    function assertSwapPreservesPoolInvariant() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredVaultIsAdopter();
        (address pool, address tokenIn, address tokenOut) = _swapArgs(ph.callinputAt(ctx.callStart));
        if (pool != POOL) {
            return;
        }

        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);

        uint256[] memory preLive = _liveBalancesAt(pre);
        uint256[] memory postLive = _liveBalancesAt(post);
        uint256 preInvariant = _invariantOf(preLive, pre);
        uint256 postInvariant = _invariantOf(postLive, post);
        require(
            postInvariant + _bpsOf(preInvariant, INVARIANT_DUST_TOLERANCE_BPS) >= preInvariant,
            "BalancerV3: swap decreased pool invariant"
        );

        require(_bptTotalSupplyAt(post) == _bptTotalSupplyAt(pre), "BalancerV3: swap changed BPT supply");

        (uint256 indexIn, uint256 indexOut) = _tokenIndexesAt(pre, tokenIn, tokenOut);
        require(postLive[indexIn] >= preLive[indexIn], "BalancerV3: swap decreased tokenIn pool balance");
        require(postLive[indexOut] <= preLive[indexOut], "BalancerV3: swap increased tokenOut pool balance");
    }

    /// @notice Vault custody must cover its reserves, and reserves must cover pool accounting.
    /// @dev The Vault tracks its own token custody in `_reservesOf` and keeps the watched pool's
    ///      balances and accrued aggregate fees as separate ledgers; nothing re-checks the three
    ///      layers against each other after settlement. At transaction end, for every registered
    ///      pool token: the Vault's real ERC20 balance must be at least its recorded reserves
    ///      (donations may exceed it), and reserves must be at least the watched pool's raw balance
    ///      plus aggregate swap and yield fees still owed to the fee controller. A failure means
    ///      tokens physically left the Vault without the accounting noticing, or pool accounting
    ///      was inflated beyond what custody can pay out.
    function assertVaultCustodyCoversPoolAccounting() external view {
        _requireConfiguredVaultIsAdopter();
        PhEvm.ForkId memory post = _postTx();
        if (!_isPoolInitializedAt(post)) {
            return;
        }

        PoolTokenSnapshot memory snap = _poolTokenSnapshotAt(post);
        for (uint256 i; i < snap.tokens.length; ++i) {
            address token = snap.tokens[i];
            uint256 reserves = _reservesOfAt(token, post);

            require(
                _readBalanceAt(token, VAULT, post) >= reserves, "BalancerV3: vault reserves exceed real token custody"
            );
            require(
                reserves >= snap.balancesRaw[i] + _aggregateFeesAt(token, post),
                "BalancerV3: pool accounting exceeds vault reserves"
            );
        }
    }

    /// @notice Rate-provider rates feeding the watched pool may not jump within one transaction.
    /// @dev Live balances (and therefore swap math, yield fees, and invariant computation) scale
    ///      WITH_RATE tokens by their provider's `getRate()`. The Vault never bounds that answer.
    ///      Rates track slow yield accrual, so any large move inside a single transaction is
    ///      manipulation or a broken provider, not yield. At transaction end every registered rate
    ///      provider must return a nonzero rate within the configured drift bound of its pre-tx
    ///      value. A failure means the transaction moved a rate the pool prices against.
    function assertTokenRatesWithinDriftBound() external view {
        _requireConfiguredVaultIsAdopter();
        PhEvm.ForkId memory preTx = _preTx();
        PhEvm.ForkId memory postTx = _postTx();
        if (!_isPoolInitializedAt(postTx)) {
            return;
        }

        PoolTokenSnapshot memory snap = _poolTokenSnapshotAt(postTx);
        for (uint256 i; i < snap.tokenInfo.length; ++i) {
            address rateProvider = snap.tokenInfo[i].rateProvider;
            if (rateProvider == address(0)) {
                continue;
            }

            uint256 postRate = _rateAt(rateProvider, postTx);
            require(postRate != 0, "BalancerV3: rate provider returned zero rate");

            uint256 preRate = _rateAt(rateProvider, preTx);
            if (preRate == 0) {
                // Provider only became live within this transaction (e.g. pool registration).
                continue;
            }

            require(
                _absDiff(postRate, preRate) <= _bpsOf(preRate, RATE_DRIFT_TOLERANCE_BPS),
                "BalancerV3: token rate moved beyond drift bound"
            );
        }
    }
}
