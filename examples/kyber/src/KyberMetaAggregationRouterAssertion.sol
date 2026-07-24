// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {KyberMetaAggregationRouterHelpers} from "./KyberMetaAggregationRouterHelpers.sol";
import {IKyberMetaAggregationRouterV2Like, SwapDescriptionV2} from "./KyberMetaAggregationRouterInterfaces.sol";

/// @title KyberMetaAggregationRouterAssertion
/// @author Phylax Systems
/// @notice Recipient-credit postcondition for KyberSwap MetaAggregationRouterV2.
/// @dev Transfer and Approval logs do not identify the spender that moved funds, so the former
///      allowance-drain heuristic is intentionally not registered. `originalRouterFamily_` must be
///      true only for deployments whose bit 0 means partial fill and which expose `swapGeneric`.
contract KyberMetaAggregationRouterAssertion is KyberMetaAggregationRouterHelpers {
    constructor(address router_, bool originalRouterFamily_)
        KyberMetaAggregationRouterHelpers(router_, originalRouterFamily_)
    {}

    /// @notice Registers the protected MetaAggregationRouterV2 settlement entry points.
    /// @dev Both checks are call-scoped so reads are bound to the exact triggered settlement.
    function triggers() external view override {
        registerFnCallTrigger(
            this.assertReceiverGetsMinReturn.selector, IKyberMetaAggregationRouterV2Like.swap.selector
        );
        if (ORIGINAL_ROUTER_FAMILY) {
            registerFnCallTrigger(
                this.assertReceiverGetsMinReturn.selector, IKyberMetaAggregationRouterV2Like.swapGeneric.selector
            );
        }
        registerFnCallTrigger(
            this.assertReceiverGetsMinReturn.selector, IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector
        );
    }

    /// @notice Legacy diagnostic retained for source compatibility; it is not registered.
    /// @dev Transfer logs cannot prove which spender used an allowance. Do not use this selector
    ///      as a production assertion.
    function assertNoThirdPartyAllowanceDrain() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredRouterIsAdopter();

        address initiator = _swapInitiator(ctx.callStart, ctx.selector);
        _assertOnlyInitiatorAllowanceExercised(ctx.callStart, initiator);
    }

    /// @notice The declared recipient must be credited at least the signed `minReturnAmount`.
    /// @dev Decodes the swap description from the triggered calldata and compares the recipient's
    ///      buy-token balance across the call as a fork-aware delta. This is path-independent
    ///      defense-in-depth: the live router already enforces min-return against this same
    ///      recipient balance delta, so the check earns its keep only if that guard is ever
    ///      bypassed (a buggy/compromised settlement path), while still pinning the user-signed
    ///      minimum from outside the router's own accounting.
    ///
    ///      Out of scope, and skipped to avoid false positives:
    ///      - zero-minimum swaps (nothing to enforce);
    ///      - native-asset payouts (`dstToken == ETH_SENTINEL`) — this surface reads ERC20 balances only;
    ///      - partial-fill orders (`_PARTIAL_FILL` flag) — the router enforces a pro-rated minimum
    ///        keyed to the actual spent amount, which a flat `minReturnAmount` floor would not match.
    ///      An unset recipient (`dstReceiver == address(0)`) is NOT skipped: the router credits
    ///      `msg.sender` in that case, so the check is retargeted to the resolved initiator.
    function assertReceiverGetsMinReturn() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredRouterIsAdopter();

        SwapDescriptionV2 memory desc = _swapDescriptionFor(ctx.selector, ph.callinputAt(ctx.callStart));
        if (
            desc.minReturnAmount == 0 || desc.dstToken == ETH_SENTINEL
                || (ORIGINAL_ROUTER_FAMILY && _flagsChecked(desc.flags, PARTIAL_FILL))
        ) {
            return;
        }

        // The router pays msg.sender when dstReceiver is unset; resolve to the initiator so the
        // default-recipient path is still protected. If the frame cannot be matched, skip.
        address receiver =
            desc.dstReceiver == address(0) ? _swapInitiator(ctx.callStart, ctx.selector) : desc.dstReceiver;
        if (receiver == address(0)) {
            return;
        }

        uint256 beforeBalance = _readBalanceAt(desc.dstToken, receiver, _preCall(ctx.callStart));
        uint256 afterBalance = _readBalanceAt(desc.dstToken, receiver, _postCall(ctx.callEnd));

        require(afterBalance >= beforeBalance, "Kyber: dstReceiver balance decreased");
        require(
            afterBalance - beforeBalance >= desc.minReturnAmount, "Kyber: dstReceiver credited below minReturnAmount"
        );
    }
}
