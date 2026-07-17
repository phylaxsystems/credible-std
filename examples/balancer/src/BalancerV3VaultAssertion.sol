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
///      to the pool contract, trusting `onSwap`'s answer. This bundle re-checks external facts
///      that no Vault `require` expresses, with these honestly-stated boundaries:
///      - The swap check asks the pool's OWN `computeInvariant`, so it detects inconsistency
///        between a pool's `onSwap` results and its own invariant math — not a pool whose
///        implementation is malicious in both functions at once. It supports hookless pools only:
///        before/after-swap hooks are intentionally reentrant in V3 and break call-boundary
///        snapshots, so hooked pools are skipped and need a pool-specific variant.
///      - The custody check is a necessary-but-not-sufficient per-pool bound: Vault reserves are
///        global across every pool and buffer, so one pool's view cannot prove aggregate solvency.
///      - The rate check bounds provider movement within transactions that touch the watched
///        pool's accounting; it is skipped in recovery mode so a broken provider can never block
///        the canonical recovery exit.
///
///      Because the Vault is shared across every V3 pool, the call-scoped swap check filters on the
///      watched pool and silently ignores swaps in other pools. Tx-end checks read only the watched
///      pool's accounting, so unrelated pool activity cannot produce false positives.
contract BalancerV3VaultAssertion is BalancerV3VaultHelpers {
    constructor(address vault_, address pool_, uint256 invariantDustTolerance_, uint256 rateDriftToleranceBps_)
        BalancerV3VaultHelpers(vault_, pool_, invariantDustTolerance_, rateDriftToleranceBps_)
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
        registerTxEndTrigger(this.assertPoolAccountingWithinVaultCustody.selector);
        registerTxEndTrigger(this.assertTokenRatesWithinDriftBound.selector);
    }

    /// @notice A swap on a hookless pool must grow (or at worst preserve) the pool invariant and
    ///         touch nothing else.
    /// @dev The Vault takes `onSwap`'s output on trust: no `require` recomputes the curve. This
    ///      check recomputes the pool's invariant from live balances through the pool's own math at
    ///      the pre-call and post-call forks. With any nonzero swap fee the invariant must grow, so
    ///      it may never drop by more than the configured absolute rounding dust. BPT supply must
    ///      be frozen across a swap, and raw pool balances must move in the swap's direction
    ///      (tokenIn in, tokenOut out).
    ///
    ///      Scope and trust boundaries, stated exactly:
    ///      - Pools with before/after-swap hooks are SKIPPED. Those hooks run inside the swap call
    ///        scope, outside the Vault's internal reentrancy guard, and may legitimately reenter
    ///        (nested liquidity, donations, nested swaps), so call-boundary snapshots cannot
    ///        isolate the core swap. Hooked pools need a variant built for their specific hook.
    ///      - For the supported hookless pools no user code can run inside the swap call, so every
    ///        registered rate must be identical at the call's boundary snapshots; that is enforced
    ///        below, which also pins one fixed rate vector under both invariant evaluations and
    ///        makes raw-balance direction equivalent to live-balance direction. Each rate observed
    ///        at swap start — the rate the Vault actually prices against — must additionally sit
    ///        within the drift bound of its pre-transaction baseline, so a rate transiently moved
    ///        between calls of one transaction and restored before tx-end is still caught at the
    ///        exact operation that consumed it.
    ///      - The invariant is recomputed by the POOL's own `computeInvariant`. This detects value
    ///        leaking through broken or inconsistent pool math (an `onSwap` whose result the
    ///        pool's own invariant function condemns), which is the failure mode of an honest but
    ///        buggy pool. A deliberately malicious pool implementation can keep `onSwap` and
    ///        `computeInvariant` mutually consistent and pass; catching that class requires
    ///        pinning trusted factory/codehash combinations and re-implementing the invariant math
    ///        independently per pool type, which is out of scope for this example.
    function assertSwapPreservesPoolInvariant() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredVaultIsAdopter();
        (address pool, address tokenIn, address tokenOut) = _swapArgs(ph.callinputAt(ctx.callStart));
        if (pool != POOL) {
            return;
        }

        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);

        if (_hasSwapHooksAt(pre)) {
            // Reentrant-by-design hook window: call-boundary snapshots cannot attribute deltas to
            // the core swap. Documented restriction — hooked pools need a pool-specific variant.
            return;
        }

        PoolTokenSnapshot memory preSnap = _poolTokenSnapshotAt(pre);
        PoolTokenSnapshot memory postSnap = _poolTokenSnapshotAt(post);

        _requireSwapRatesPinned(preSnap, pre, post);

        uint256 preInvariant = _invariantOf(_liveBalancesAt(pre), pre);
        uint256 postInvariant = _invariantOf(_liveBalancesAt(post), post);
        require(postInvariant + INVARIANT_DUST_TOLERANCE >= preInvariant, "BalancerV3: swap decreased pool invariant");

        require(_bptTotalSupplyAt(post) == _bptTotalSupplyAt(pre), "BalancerV3: swap changed BPT supply");

        (uint256 indexIn, uint256 indexOut) = _tokenIndexes(preSnap.tokens, tokenIn, tokenOut);
        require(
            postSnap.balancesRaw[indexIn] >= preSnap.balancesRaw[indexIn],
            "BalancerV3: swap decreased tokenIn pool balance"
        );
        require(
            postSnap.balancesRaw[indexOut] <= preSnap.balancesRaw[indexOut],
            "BalancerV3: swap increased tokenOut pool balance"
        );
    }

    /// @dev Rate discipline for one matched hookless swap call: every registered provider must
    ///      report the same rate at both call boundaries (nothing may move a rate inside a
    ///      hookless swap), and the swap-start rate — the one the Vault prices against — must sit
    ///      within the drift bound of the provider's pre-transaction baseline. A provider that did
    ///      not answer at the pre-tx fork did not exist yet (pool deployed within this
    ///      transaction) and has no baseline to compare; a provider that answered zero is a broken
    ///      baseline and fails instead of being conflated with the deployment case.
    function _requireSwapRatesPinned(PoolTokenSnapshot memory snap, PhEvm.ForkId memory pre, PhEvm.ForkId memory post)
        internal
        view
    {
        for (uint256 i; i < snap.tokenInfo.length; ++i) {
            address rateProvider = snap.tokenInfo[i].rateProvider;
            if (rateProvider == address(0)) {
                continue;
            }

            uint256 rateAtSwap = _rateAt(rateProvider, pre);
            require(rateAtSwap == _rateAt(rateProvider, post), "BalancerV3: rate moved within swap call");

            (bool answered, uint256 baseline) = _rateStatusAt(rateProvider, _preTx());
            if (!answered) {
                continue;
            }
            require(baseline != 0, "BalancerV3: zero rate baseline");
            require(
                _absDiff(rateAtSwap, baseline) <= _bpsOf(baseline, RATE_DRIFT_TOLERANCE_BPS),
                "BalancerV3: swap priced against rate beyond drift bound"
            );
        }
    }

    /// @notice The watched pool's accounting must stay within the Vault's recorded reserves, and
    ///         reserves must stay within real token custody.
    /// @dev NECESSARY BUT NOT SUFFICIENT, by construction: `getReservesOf` is one global ledger
    ///      shared by every pool and every ERC-4626 buffer in the singleton, so a single pool's
    ///      claims sitting under the global number proves nothing about aggregate solvency —
    ///      other pools' and buffers' claims consume the same headroom, and detecting that
    ///      requires enumerating every registered pool, which a one-pool example cannot do. What
    ///      this bound DOES catch, at transaction end and per registered pool token: real ERC20
    ///      custody falling below recorded reserves (tokens physically left without the ledger
    ///      noticing; donations may exceed it, so `>=`), and the watched pool's raw balance plus
    ///      its accrued aggregate swap/yield fees exceeding global reserves (this pool's
    ///      accounting inflated beyond anything custody could pay out).
    function assertPoolAccountingWithinVaultCustody() external view {
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

    /// @notice Rate-provider rates feeding the watched pool may not jump within one transaction
    ///         that touches the pool's accounting.
    /// @dev Live balances (and therefore swap math, yield fees, and invariant computation) scale
    ///      WITH_RATE tokens by their provider's `getRate()`. The Vault never bounds that answer.
    ///      Rates track slow yield accrual, so any large move inside a single transaction is
    ///      manipulation or a broken provider, not yield.
    ///
    ///      Scope, so the watched provider never becomes a liveness dependency for the rest of
    ///      the singleton:
    ///      - Runs only when the transaction changed the watched pool's accounting (raw balances,
    ///        BPT supply, or aggregate fees). Unrelated-pool and buffer traffic never calls the
    ///        watched provider. Residual: a transaction that moves a rate without touching the
    ///        pool is not examined here — but any later transaction that consumes the moved rate
    ///        touches the pool, and the swap check separately pins each consumed rate to that
    ///        transaction's own baseline.
    ///      - Skipped entirely when the pool is in recovery mode post-transaction: Balancer's
    ///        recovery exit deliberately uses raw balances precisely because providers may be
    ///        broken, and a reverting provider must not block that path.
    ///      - A provider already registered for the pool before the transaction MUST answer with a
    ///        nonzero pre-tx rate: a missing or zero baseline fails instead of exempting, so a
    ///        provider that "successfully returns zero" cannot use the deployment exemption to
    ///        legitimize an arbitrary post-tx rate. Only a provider absent from the pre-tx
    ///        registration (pool registered within this transaction) skips the drift comparison.
    function assertTokenRatesWithinDriftBound() external view {
        _requireConfiguredVaultIsAdopter();
        PhEvm.ForkId memory preTx = _preTx();
        PhEvm.ForkId memory postTx = _postTx();
        if (!_isPoolInitializedAt(postTx)) {
            return;
        }
        if (_isPoolInRecoveryModeAt(postTx)) {
            return;
        }

        PoolTokenSnapshot memory postSnap = _poolTokenSnapshotAt(postTx);

        bool initializedPreTx = _isPoolInitializedAt(preTx);
        PoolTokenSnapshot memory preSnap;
        if (initializedPreTx) {
            preSnap = _poolTokenSnapshotAt(preTx);
            if (!_poolAccountingChanged(preSnap, postSnap, preTx, postTx)) {
                return;
            }
        }

        for (uint256 i; i < postSnap.tokenInfo.length; ++i) {
            address rateProvider = postSnap.tokenInfo[i].rateProvider;
            if (rateProvider == address(0)) {
                continue;
            }

            uint256 postRate = _rateAt(rateProvider, postTx);
            require(postRate != 0, "BalancerV3: rate provider returned zero rate");

            if (!initializedPreTx || !_providerRegisteredIn(preSnap, rateProvider)) {
                // Provider registered within this transaction (pool deployment flow): no pre-tx
                // baseline exists by construction, so only the nonzero post-state is enforceable.
                continue;
            }

            (bool answered, uint256 preRate) = _rateStatusAt(rateProvider, preTx);
            require(answered && preRate != 0, "BalancerV3: zero rate baseline");
            require(
                _absDiff(postRate, preRate) <= _bpsOf(preRate, RATE_DRIFT_TOLERANCE_BPS),
                "BalancerV3: token rate moved beyond drift bound"
            );
        }
    }

    /// @dev Whether the transaction changed the watched pool's accounting: raw balances, BPT
    ///      supply, or accrued aggregate fees. Live balances are deliberately excluded — they move
    ///      when a rate moves even if the pool was never touched, and using them would reintroduce
    ///      the provider as a dependency of unrelated transactions.
    function _poolAccountingChanged(
        PoolTokenSnapshot memory preSnap,
        PoolTokenSnapshot memory postSnap,
        PhEvm.ForkId memory preTx,
        PhEvm.ForkId memory postTx
    ) internal view returns (bool) {
        if (preSnap.balancesRaw.length != postSnap.balancesRaw.length) {
            return true;
        }
        for (uint256 i; i < preSnap.balancesRaw.length; ++i) {
            if (preSnap.balancesRaw[i] != postSnap.balancesRaw[i]) {
                return true;
            }
        }
        if (_bptTotalSupplyAt(preTx) != _bptTotalSupplyAt(postTx)) {
            return true;
        }
        for (uint256 i; i < postSnap.tokens.length; ++i) {
            if (_aggregateFeesAt(postSnap.tokens[i], preTx) != _aggregateFeesAt(postSnap.tokens[i], postTx)) {
                return true;
            }
        }
        return false;
    }
}
