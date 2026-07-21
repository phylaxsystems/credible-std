// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AnomalyGatedBaseAssertion} from "./AnomalyGatedBaseAssertion.sol";

/// @title AnomalyCompositeAssertion
/// @author Phylax Systems
/// @notice One anomaly-gated assertion that combines several damage heuristics under a single
///         operator, AND or OR, in one function.
///
/// Invariant covered:
///   - **Gated composite damage**: an anomalous transaction may not corroborate the enabled damage
///     set under the chosen operator. Under OR any one heuristic blocks; under AND every enabled
///     heuristic must corroborate.
///
/// @dev A fleet of single-heuristic assertions can only OR: each is its own contract and any revert
///      invalidates the transaction, so several `AnomalyGated*` contracts compute
///      `a AND (h1 OR h2 OR ...)`. A fleet cannot express two things:
///
///        1. `Operator::And` across heuristics, `a AND (h1 AND h2)`. Reverting is disjunctive across
///           contracts, so a conjunction has to live in one function. The offline sweep searches AND
///           configs; deploying an AND selection as separate contracts would ship a different
///           predicate than the one whose friction and detection were measured.
///        2. The exclusive-set fall-through `a AND NOT(h1) AND NOT(h2) ...`, a conjunction of
///           negations. It must be a non-revert outcome of the same evaluation that would otherwise
///           block, or the alert cell is not derivable.
///
///      The disposition (see `AnomalyGatedBaseAssertion`): `block = a AND H` reverts, `pass = NOT a`
///      returns early, and `alert = a AND NOT H` falls through without reverting.
///
///      The corroboration reads use the base primitives, the same ones the individual mixins call.
///      Deploy one composite per protocol, parameters as the only difference. Override `_extra` to
///      fold a protocol-specific leg into the operator.
contract AnomalyCompositeAssertion is AnomalyGatedBaseAssertion {
    /// @notice Reverts when the enabled damage set corroborates under the operator (`block = a AND H`).
    error AnomalousDamage();
    /// @notice Reverts on an anomalous transaction when no heuristic is enabled: the bare-gate
    ///         baseline, block on the score alone. Reachable only when `bareGateBaseline` allowed
    ///         the heuristic-free deploy; deployed only to measure the baseline.
    error AnomalousBareGate();
    /// @notice Constructor guard: a `Config` with no heuristic enabled would block on the model
    ///         score alone, which must be the explicit `bareGateBaseline` choice rather than a
    ///         default-initialized struct.
    error NoHeuristicEnabled();

    /// @notice The enabled heuristics and their parameters. Each field becomes an immutable in the
    ///         constructor, except `oracleQuery` (a `bytes`, which cannot be immutable) held in
    ///         storage, and `bareGateBaseline`, which only gates the constructor.
    struct Config {
        address target;
        uint16 anomalyThresholdBps;
        bool requireAll; // true: block on AND of the enabled heuristics; false: OR
        bool bareGateBaseline; // explicit opt-in: with no heuristic enabled, block on the score alone
        bool useDrain;
        address outflowTarget;
        address outflowToken;
        uint256 outflowFracBps;
        bool useUpgrade;
        address upgradeTarget; // address(0): watch `target`
        bytes32 ownerSlot;
        bool useAccounting;
        address accountingVault;
        uint256 shareToleranceBps;
        bool useOracle;
        address oracle;
        bytes oracleQuery;
        uint256 oracleToleranceBps;
    }

    bool internal immutable requireAll;
    bool internal immutable useDrain;
    address internal immutable outflowTarget;
    address internal immutable outflowToken;
    uint256 internal immutable outflowFracBps;
    bool internal immutable useUpgrade;
    address internal immutable upgradeTarget;
    bytes32 internal immutable ownerSlot;
    bool internal immutable useAccounting;
    address internal immutable accountingVault;
    uint256 internal immutable shareToleranceBps;
    bool internal immutable useOracle;
    address internal immutable oracle;
    uint256 internal immutable oracleToleranceBps;
    /// @dev Stored, not immutable: `bytes` cannot be immutable. Read only when `useOracle`.
    bytes internal oracleQuery;

    constructor(Config memory c) AnomalyGatedBaseAssertion(c.target, c.anomalyThresholdBps) {
        if (!(c.bareGateBaseline || c.useDrain || c.useUpgrade || c.useAccounting || c.useOracle)) {
            revert NoHeuristicEnabled();
        }
        // Each enabled leg must carry the parameters it reads; a zero address leaves the leg
        // silently inert or falsely blocking. The drain fraction must sit in [1, 10_000]: zero
        // corroborates on any transaction, and above 10_000 can never corroborate because net
        // outflow is capped by the pre-transaction balance. The upgrade leg needs no check: a zero
        // `upgradeTarget` means `target`.
        if (
            c.useDrain
                && (c.outflowTarget == address(0)
                    || c.outflowToken == address(0)
                    || c.outflowFracBps == 0
                    || c.outflowFracBps > 10_000)
        ) {
            revert HeuristicMisconfigured();
        }
        if (c.useAccounting && c.accountingVault == address(0)) {
            revert HeuristicMisconfigured();
        }
        if (c.useOracle && (c.oracle == address(0) || c.oracleQuery.length < 4)) {
            revert HeuristicMisconfigured();
        }
        requireAll = c.requireAll;
        useDrain = c.useDrain;
        outflowTarget = c.outflowTarget;
        outflowToken = c.outflowToken;
        outflowFracBps = c.outflowFracBps;
        useUpgrade = c.useUpgrade;
        upgradeTarget = c.upgradeTarget;
        ownerSlot = c.ownerSlot;
        useAccounting = c.useAccounting;
        accountingVault = c.accountingVault;
        shareToleranceBps = c.shareToleranceBps;
        useOracle = c.useOracle;
        oracle = c.oracle;
        oracleQuery = c.oracleQuery;
        oracleToleranceBps = c.oracleToleranceBps;
    }

    function triggers() external view virtual override {
        _registerAnomalyTrigger(this.assertComposite.selector);
    }

    /// @notice The composite block predicate. Non-view because the oracle leg executes a read.
    /// @dev Folds each enabled heuristic into the operator, skipping the remaining reads once the
    ///      fold hits the operator's absorbing value: a silent leg under AND, a corroborating leg
    ///      under OR. The alert cell (`a AND NOT H`) is the deliberate fall-through with no revert.
    function assertComposite() external {
        if (!_anomalous()) {
            return; // pass: not anomalous
        }

        bool anyEnabled;
        bool corroborated = requireAll; // the operator's identity: AND folds from true, OR from false

        if (useDrain && !_decided(corroborated)) {
            anyEnabled = true;
            corroborated = _fold(corroborated, _drains(outflowTarget, outflowToken, outflowFracBps));
        }
        if (useUpgrade && !_decided(corroborated)) {
            anyEnabled = true;
            corroborated = _fold(corroborated, _upgraded(upgradeTarget, ownerSlot));
        }
        if (useAccounting && !_decided(corroborated)) {
            anyEnabled = true;
            corroborated = _fold(corroborated, _accountingBroke(accountingVault, shareToleranceBps));
        }
        if (useOracle && !_decided(corroborated)) {
            anyEnabled = true;
            corroborated = _fold(corroborated, _oracleDeviated(oracle, oracleQuery, oracleToleranceBps));
        }
        if (!_decided(corroborated)) {
            (bool extraEnabled, bool extraCorroborates) = _extra();
            if (extraEnabled) {
                anyEnabled = true;
                corroborated = _fold(corroborated, extraCorroborates);
            }
        }

        if (!anyEnabled) {
            // Only a `bareGateBaseline` deploy reaches this: the constructor guard requires a
            // heuristic otherwise, and the first enabled leg always runs before the fold can decide.
            revert AnomalousBareGate();
        }
        if (corroborated) {
            revert AnomalousDamage(); // block = a AND H
        }
        // a AND NOT H: the exclusive set. Fall through, no revert; the executor surfaces the alert.
    }

    /// @dev The operator's fold over one leg: AND or OR of the accumulator and the leg.
    function _fold(bool acc, bool leg) internal view returns (bool) {
        return requireAll ? acc && leg : acc || leg;
    }

    /// @dev Whether the fold has hit the operator's absorbing value (false under AND, true under
    ///      OR). Past it the remaining legs cannot change the outcome, so their reads are skipped.
    function _decided(bool acc) internal view returns (bool) {
        return acc != requireAll;
    }

    /// @notice A protocol-specific corroboration leg folded into the operator alongside the generic
    ///         heuristics. Override in a subclass to add a protocol invariant the generic set cannot express.
    /// @dev The constructor guard cannot see a subclass leg, so a subclass whose only leg is
    ///      `_extra` must set `bareGateBaseline` to deploy; the bare-gate fall-back then fires only
    ///      when the leg reports itself disabled.
    /// @return enabled Whether the leg participates in the operator.
    /// @return corroborates Whether the leg corroborates damage on this transaction.
    function _extra() internal virtual returns (bool enabled, bool corroborates) {
        return (false, false);
    }
}
