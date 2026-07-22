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
    /// @notice Whether the watched pool was registered with a before- or after-swap hook.
    /// @dev Balancer fixes hook wiring when a pool is registered, so classifying it once at
    ///      deployment avoids an expensive full hook-config read on every swap.
    bool internal immutable POOL_HAS_SWAP_HOOKS;

    constructor(
        address vault_,
        address pool_,
        bool poolHasSwapHooks_,
        uint256 invariantDustTolerance_,
        uint256 rateDriftToleranceBps_
    ) BalancerV3VaultHelpers(vault_, pool_, invariantDustTolerance_, rateDriftToleranceBps_) {
        POOL_HAS_SWAP_HOOKS = poolHasSwapHooks_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers Vault selectors against their protection assertions.
    /// @dev The Vault is the assertion adopter. The swap check is call-scoped so it compares the
    ///      exact pre-call and post-call snapshots of the matched operation. The transaction-end
    ///      checks gate on the watched pool's own accounting deltas — a bounded number of Vault
    ///      storage reads — never on the transaction's call trace: the Vault is a singleton, so a
    ///      trace scan would copy every matching call's calldata into the assertion and let one
    ///      heavy batch transaction (or a deliberately calldata-padded one) exhaust the assertion's
    ///      fixed gas budget and false-positively invalidate itself.
    function triggers() external view override {
        registerFnCallTrigger(this.assertSwapPreservesPoolInvariant.selector, IBalancerV3VaultLike.swap.selector);
        registerFnCallTrigger(
            this.assertOperationRatesWithinBaseline.selector, IBalancerV3VaultLike.addLiquidity.selector
        );
        registerFnCallTrigger(
            this.assertOperationRatesWithinBaseline.selector, IBalancerV3VaultLike.removeLiquidity.selector
        );
        registerFnCallTrigger(
            this.assertOperationRatesWithinBaseline.selector, IBalancerV3VaultLike.initialize.selector
        );
        registerFnCallTrigger(
            this.assertOperationRatesWithinBaseline.selector, IBalancerV3VaultLike.disableRecoveryMode.selector
        );
        registerTxEndTrigger(this.assertPoolAccountingWithinVaultCustody.selector);
        registerTxEndTrigger(this.assertTokenRatesWithinDriftBound.selector);
    }

    /// @notice A swap on a hookless pool must grow (or at worst preserve) the pool invariant,
    ///         leave BPT supply unchanged, and move its live tokenOut balance in the swap's
    ///         direction.
    /// @dev The Vault takes `onSwap`'s output on trust: no `require` recomputes the curve. This
    ///      check recomputes the pool's invariant from live balances through the pool's own math at
    ///      the pre-call and post-call forks. With any nonzero swap fee the invariant must grow, so
    ///      it may never drop by more than the configured absolute rounding dust. The
    ///      fee-adjusted live tokenOut balance may not increase. Together with invariant
    ///      non-decrease, this implies nonnegative value entered on the tokenIn side for
    ///      Balancer's monotonic pool invariants without a redundant input-leg comparison.
    ///
    ///      Scope and trust boundaries, stated exactly:
    ///      - Pools configured at assertion deployment as having before/after-swap hooks are
    ///        SKIPPED. Those hooks run inside the swap call scope, outside the Vault's internal
    ///        reentrancy guard, and may legitimately reenter (nested liquidity, donations, nested
    ///        swaps), so call-boundary snapshots cannot isolate the core swap. Hooked pools need a
    ///        variant built for their specific hook.
    ///      - Supported hookless pools expose no state-changing callback inside the swap, so the
    ///        registered rate vector cannot move between its call-boundary snapshots. Each rate
    ///        observed at swap start — the rate the Vault actually prices against — must sit
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
        if (POOL_HAS_SWAP_HOOKS) {
            return;
        }

        PhEvm.TriggerContext memory ctx = ph.context();
        (address pool, address tokenOut) = _swapPoolAndTokenOut(ph.callinputAt(ctx.callStart));
        if (pool != POOL) {
            return;
        }

        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);

        PoolTokenSnapshot memory preSnap = _poolTokenSnapshotAt(pre);

        _requireSwapRatesWithinBaseline(preSnap, pre);

        uint256[] memory preLiveBalances = _liveBalancesAt(pre);
        uint256[] memory postLiveBalances = _liveBalancesAt(post);
        uint256 preInvariant = _invariantOf(preLiveBalances, pre);
        uint256 postInvariant = _invariantOf(postLiveBalances, post);
        require(postInvariant + INVARIANT_DUST_TOLERANCE >= preInvariant, "BalancerV3: swap decreased pool invariant");

        require(_bptTotalSupplyAt(post) == _bptTotalSupplyAt(pre), "BalancerV3: swap changed BPT supply");

        uint256 indexOut = _tokenIndex(preSnap.tokens, tokenOut);
        require(
            postLiveBalances[indexOut] <= preLiveBalances[indexOut], "BalancerV3: swap increased tokenOut pool balance"
        );
    }

    /// @dev Rate discipline for one matched hookless swap call: the swap-start rate — the one the
    ///      Vault prices against — must sit within the drift bound of the provider's
    ///      pre-transaction baseline. Hookless swaps expose no state-changing callback, so the
    ///      provider cannot move inside the call. A provider that did not answer at the pre-tx
    ///      fork did not exist yet (pool deployed within this transaction) and has no baseline to
    ///      compare; a provider that answered zero is a broken baseline and fails instead of being
    ///      conflated with the deployment case.
    function _requireSwapRatesWithinBaseline(PoolTokenSnapshot memory snap, PhEvm.ForkId memory pre) internal view {
        _requireRatesWithinBaseline(snap, pre, "BalancerV3: swap priced against rate beyond drift bound");
    }

    /// @notice Pins rates consumed by liquidity and recovery-resync operations to their transaction baseline.
    /// @dev This closes the router-shaped manipulate-operation-restore gap for both liquidity
    ///      selectors. A pool with state-changing liquidity hooks needs a pool-specific assertion
    ///      that observes the rate after its before hook, since an outer call snapshot cannot see a
    ///      rate moved and restored entirely inside that hook lifecycle.
    function assertOperationRatesWithinBaseline() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        address pool = ctx.selector == IBalancerV3VaultLike.addLiquidity.selector
            || ctx.selector == IBalancerV3VaultLike.removeLiquidity.selector
            ? _operationPool(input)
            : _firstAddressArg(input);
        if (pool != POOL) {
            return;
        }

        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PoolTokenSnapshot memory preSnap = _poolTokenSnapshotAt(pre);
        _requireRatesWithinBaseline(preSnap, pre, "BalancerV3: liquidity priced against rate beyond drift bound");
    }

    function _requireRatesWithinBaseline(
        PoolTokenSnapshot memory snap,
        PhEvm.ForkId memory pre,
        string memory driftError
    ) internal view {
        PhEvm.ForkId memory preTx = _preTx();
        for (uint256 i; i < snap.tokenInfo.length; ++i) {
            address rateProvider = snap.tokenInfo[i].rateProvider;
            if (rateProvider == address(0)) {
                continue;
            }

            uint256 rateAtOperation = _rateAt(rateProvider, pre);

            (bool answered, uint256 baseline) = _rateStatusAt(rateProvider, preTx);
            if (!answered) {
                continue;
            }
            require(baseline != 0, "BalancerV3: zero rate baseline");
            require(_absDiff(rateAtOperation, baseline) <= _bpsOf(baseline, RATE_DRIFT_TOLERANCE_BPS), driftError);
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
    ///
    ///      Gating: the check runs only when the watched pool's own accounting moved across the
    ///      transaction (raw balances, BPT supply, aggregate fees — all plain Vault storage
    ///      reads). Every read here is bounded by the pool's token count, so the assertion's cost
    ///      is independent of how large or call-heavy the triggering transaction is, and unrelated
    ///      singleton traffic never depends on the watched pool's tokens answering. Residual:
    ///      reserves and real custody are global and can move without a watched-pool accounting
    ///      delta, so a violation introduced by such a transaction surfaces at the pool's next
    ///      accounting-moving transaction instead of the causing one — triggered this way for
    ///      efficiency reasons.
    function assertPoolAccountingWithinVaultCustody() external view {
        _requireConfiguredVaultIsAdopter();
        PhEvm.ForkId memory post = _postTx();
        if (!_isPoolInitializedAt(post)) {
            return;
        }

        PoolTokenSnapshot memory snap = _poolTokenSnapshotAt(post);
        if (!_watchedPoolAccountingChangedTxWide(snap, post)) {
            // The gate keys on the watched pool's accounting only. Reserves and real custody can
            // move without it (shared-token traffic from other pools and buffers), so a violation
            // caused by such a transaction is examined at the next accounting-moving transaction
            // rather than at the causing one — triggered this way for efficiency reasons.
            return;
        }
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

    /// @dev Tx-wide gate for the custody check, built exclusively from Vault storage reads about
    ///      the watched pool. A pool that was not initialized before the transaction is treated as
    ///      changed (this is its initialization transaction; the pre-tx token snapshot does not
    ///      exist to compare against). Deliberately NOT a call-trace scan: `getCallInputs` /
    ///      `matchingCalls` copy every matching call's full calldata into the assertion, so one
    ///      transaction carrying enough successful Vault calldata (a huge batch, or a swap padded
    ///      with megabytes of `userData`) would exhaust the assertion's fixed gas budget and
    ///      invalidate itself spuriously. The storage gate's cost is bounded by the pool's token
    ///      count no matter what the transaction did.
    function _watchedPoolAccountingChangedTxWide(PoolTokenSnapshot memory postSnap, PhEvm.ForkId memory postTx)
        internal
        view
        returns (bool)
    {
        PhEvm.ForkId memory preTx = _preTx();
        if (!_isPoolInitializedAt(preTx)) {
            return true;
        }
        PoolTokenSnapshot memory preSnap = _poolTokenSnapshotAt(preTx);
        return _poolAccountingChanged(preSnap, postSnap, preTx, postTx);
    }
}
