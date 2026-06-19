// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title LidoEasyTrackFlashLoanAssertion
/// @author Phylax Systems
/// @notice Blocks flash-loaned governance power from being exercised against a Lido governance
///         contract (the motivating case is EasyTrack), without upgrading the governance contract.
/// @dev Apply to the governance contract itself (e.g. EasyTrack) — the account that receives the
///      flash-loan-sensitive calls. Configure it with the governance token (LDO) and the set of
///      function selectors whose effect is weighted by `governanceToken` balance.
///
///      ## The vulnerability (from the Lido call)
///      EasyTrack is optimistic governance: whitelisted factories create *motions* that execute
///      after an objection window unless LDO holders object past a threshold. An objection's weight
///      is read from the governance token at the motion's snapshot block, and that snapshot is taken
///      at the block the motion *starts* rather than the block before. Because a same-block balance
///      read returns the live balance, an attacker can, in a single transaction, **flash-loan LDO,
///      exercise the balance-weighted action, and repay the loan** — borrowed voting power that was
///      never actually held counts. EasyTrack is not upgradable, so the snapshot cannot simply be
///      moved to `block.number - 1`; an external execution gate is the agile patch.
///
///      ## The invariant
///      Voting power exercised against the protected selectors must be power the actor *already held
///      at the start of the transaction* — not power acquired within the same transaction. A flash
///      loan is exactly the act of acquiring (and returning) the token inside one transaction, so an
///      actor whose `governanceToken` balance is larger at the moment of the governance call than it
///      was at the start of the transaction is using power it did not durably hold. This re-creates
///      the "snapshot a block earlier" property from the outside: same-block (flash-loaned) balance
///      no longer counts, because the transaction that relies on it is never included.
///
///      ## Two detection layers (the two approaches discussed on the call), both armable
///      - **`assertNoFlashLoanedVotingPower` (primary, precise).** For the protected call that fired
///        this invocation, compare the caller's `governanceToken` balance at the start of the
///        transaction (`PreTx`) against its balance immediately before the governance call executes
///        (`PreCall`). Any increase beyond `maxIntraTxAcquired` means voting power was sourced within
///        the transaction — revert. This reads the balance at *exactly* the point the governance
///        snapshot would, so it neither misses a borrow that lands just before the call nor flags a
///        borrow that was already repaid before it.
///      - **`assertNoSameTxGovTokenInflow` (corroborating, coarser).** For the firing call's caller,
///        sum the gross `governanceToken` transferred *to* it anywhere in the transaction. Any inflow
///        beyond `maxIntraTxAcquired` reverts. This is the "read the transfer logs" approach: cheaper
///        and it catches power routed through the caller even if intermediate balances net out, at the
///        cost of also flagging an actor who legitimately receives the token and acts in the same
///        transaction. Arm it alongside the primary layer when the governance entrypoint can be
///        reached by a contract that only holds the token transiently.
///
///      Both layers are wired with `registerFnCallTrigger`, so each fires once per matching protected
///      call with the firing call exposed via `ph.context()` — a transaction that does not touch
///      governance pays nothing, and a transaction with multiple protected calls checks each exactly
///      once instead of re-scanning every call on every invocation.
contract LidoEasyTrackFlashLoanAssertion is Assertion {
    /// @notice The governance contract this assertion protects (the assertion adopter). Protected
    ///         selectors are matched against calls received here.
    address public immutable governanceContract;

    /// @notice The balance-weighted governance token (LDO). Voting power is its `balanceOf`.
    address public immutable governanceToken;

    /// @notice Per-actor, per-transaction allowance of newly-acquired governance power, in token
    ///         units. Zero (the default and recommended value) forbids any intra-transaction
    ///         acquisition. A non-zero value tolerates small legitimate same-transaction top-ups.
    uint256 public immutable maxIntraTxAcquired;

    /// @notice Function selectors on `governanceContract` whose effect is weighted by
    ///         `governanceToken` balance and must therefore be protected from flash-loaned power
    ///         (e.g. `EasyTrack.objectToMotion(uint256)`).
    bytes4[] public protectedSelectors;

    constructor(
        address governanceContract_,
        address governanceToken_,
        uint256 maxIntraTxAcquired_,
        bytes4[] memory protectedSelectors_
    ) {
        require(governanceContract_ != address(0), "LidoGov: zero governance contract");
        require(governanceToken_ != address(0), "LidoGov: zero governance token");
        require(protectedSelectors_.length != 0, "LidoGov: no protected selectors");

        governanceContract = governanceContract_;
        governanceToken = governanceToken_;
        maxIntraTxAcquired = maxIntraTxAcquired_;

        for (uint256 i; i < protectedSelectors_.length; ++i) {
            require(protectedSelectors_[i] != bytes4(0), "LidoGov: zero selector");
            protectedSelectors.push(protectedSelectors_[i]);
        }

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires both detection layers to every protected selector.
    /// @dev Each protected selector gets an `onFnCall` trigger for both assertion functions, so the
    ///      armed layer fires once per matching call with the firing call available via `ph.context()`.
    ///      An operator arms whichever layer(s) they want; only the armed function executes, and only
    ///      when its selector is called on the governance contract.
    function triggers() external view override {
        for (uint256 i; i < protectedSelectors.length; ++i) {
            registerFnCallTrigger(this.assertNoFlashLoanedVotingPower.selector, protectedSelectors[i]);
            registerFnCallTrigger(this.assertNoSameTxGovTokenInflow.selector, protectedSelectors[i]);
        }
    }

    /// @notice Primary layer: forbids exercising governance power acquired within the transaction.
    /// @dev Scoped to the single protected call that fired this invocation (`ph.context()`): the
    ///      caller's governance-token balance immediately before that call (`PreCall`) must not exceed
    ///      its balance at the start of the transaction (`PreTx`) by more than `maxIntraTxAcquired`.
    ///      Reading at `PreCall` aligns with what the governance snapshot sees: a flash loan repaid
    ///      before the call reads back to baseline and passes; a flash loan still held at the call
    ///      shows the inflated balance and trips. The trigger fires once per protected call, so there
    ///      is no need to re-scan every selector and every matching call here.
    function assertNoFlashLoanedVotingPower() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        address actor = _triggerCaller(ctx);

        uint256 atTxStart = _readBalanceAt(governanceToken, actor, _preTx());
        uint256 atCall = _readBalanceAt(governanceToken, actor, _preCall(ctx.callStart));

        require(atCall <= atTxStart + maxIntraTxAcquired, "LidoGov: flash-loaned voting power");
    }

    /// @notice Corroborating layer: forbids same-transaction governance-token inflow to an actor
    ///         that exercises governance.
    /// @dev Scoped to the firing protected call's caller (`ph.context()`): the *gross* amount of
    ///      `governanceToken` transferred to it anywhere in the transaction must not exceed
    ///      `maxIntraTxAcquired`. Gross, not net, on purpose: a flash loan is borrowed and repaid
    ///      within the transaction, so its net effect on the actor is zero — only the gross inbound
    ///      leg reveals it. This reads the raw transfer log (`getErc20Transfers`) rather than the
    ///      reduced per-account deltas, precisely because the reduced view nets the round trip away.
    ///      Coarser than the primary layer (it also flags an actor that legitimately receives the
    ///      token and acts in the same transaction), but it catches power routed through a
    ///      transiently-funded caller. Arm it as defense in depth.
    function assertNoSameTxGovTokenInflow() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        address actor = _triggerCaller(ctx);

        PhEvm.Erc20TransferData[] memory deltas = ph.getErc20Transfers(governanceToken, _postTx());

        uint256 inbound;
        for (uint256 d; d < deltas.length; ++d) {
            if (deltas[d].to == actor) {
                inbound += deltas[d].value;
            }
        }

        require(inbound <= maxIntraTxAcquired, "LidoGov: same-tx governance token inflow");
    }

    /// @notice Resolves the caller of the protected call that fired this invocation.
    /// @dev `ph.context()` identifies the firing call by `callStart`; matching it against the
    ///      selector-filtered `getCallInputs` view yields that call's caller. `getCallInputs` is used
    ///      rather than `matchingCalls` so the assertion remains executable under `pcl test`.
    function _triggerCaller(PhEvm.TriggerContext memory ctx) private view returns (address) {
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(governanceContract, ctx.selector);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == ctx.callStart) return calls[i].caller;
        }
        revert("LidoGov: trigger call not found");
    }
}
