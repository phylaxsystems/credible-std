// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {KyberMetaAggregationRouterHelpers} from "./KyberMetaAggregationRouterHelpers.sol";
import {IKyberMetaAggregationRouterV2Like, SwapDescriptionV2} from "./KyberMetaAggregationRouterInterfaces.sol";

/// @title KyberMetaAggregationRouterAssertionBase
/// @author Phylax Systems
/// @notice Shared distinct-token ERC20 recipient-credit postcondition for KyberSwap routers.
/// @dev This is deliberately a narrow defense-in-depth call postcondition, not a universal
///      protocol invariant. Same-token, native-output, rebasing/reflection, and genuinely
///      pro-rated partial-fill routes are outside its additive balance-delta model.
abstract contract KyberMetaAggregationRouterAssertionBase is KyberMetaAggregationRouterHelpers {
    constructor(address router_) KyberMetaAggregationRouterHelpers(router_) {}

    function _registerTriggers(bytes4[] memory selectors) internal view {
        for (uint256 i; i < selectors.length; ++i) {
            registerFnCallTrigger(this.assertReceiverGetsMinReturn.selector, selectors[i]);
        }
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

    /// @notice Checks a distinct, non-rebasing ERC20 receiver gets the applicable flat minimum.
    /// @dev The call-scoped check intentionally duplicates Kyber's receiver balance-delta guard as
    ///      defense in depth for a buggy or compromised settlement path. It skips accounting
    ///      domains where the outer-call delta is not equivalent to Kyber's internal window.
    ///
    ///      Out of scope, and skipped to avoid false positives:
    ///      - zero-minimum swaps (nothing to enforce);
    ///      - native-asset payouts (`dstToken == ETH_SENTINEL`);
    ///      - same-token routes, because Kyber snapshots after the source debit while this assertion
    ///        snapshots around the outer call;
    ///      - original-family partial fills only when the selected entry point makes the live router
    ///        compute `spentAmount` from a balance delta rather than fixing it to `desc.amount`.
    ///      An unset recipient (`dstReceiver == address(0)`) is NOT skipped: the router credits
    ///      `msg.sender` in that case, so the check is retargeted to the resolved initiator.
    function assertReceiverGetsMinReturn() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredRouterIsAdopter();

        SwapDescriptionV2 memory desc = _swapDescriptionFor(ctx.selector, ph.callinputAt(ctx.callStart));
        if (
            desc.minReturnAmount == 0 || desc.dstToken == ETH_SENTINEL || desc.srcToken == desc.dstToken
                || _usesProRatedMinimum(ctx.selector, desc)
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

    /// @dev Modern-family deployments override this with `false`: bit zero is otherwise ignored.
    function _usesProRatedMinimum(bytes4 selector, SwapDescriptionV2 memory desc) internal pure virtual returns (bool);
}

/// @title KyberOriginalMetaAggregationRouterAssertion
/// @notice Assertion artifact for the verified original router family with `swapGeneric`.
/// @dev The artifact fixes original-family semantics at compile time; deployers cannot select a
///      caller-controlled-bit interpretation with a constructor boolean.
contract KyberOriginalMetaAggregationRouterAssertion is KyberMetaAggregationRouterAssertionBase {
    constructor(address router_) KyberMetaAggregationRouterAssertionBase(router_) {}

    /// @notice Registers all verified original-family settlement entry points.
    function triggers() external view override {
        _registerTriggers(protectedSelectors());
    }

    /// @notice Returns the selector manifest consumed directly by `triggers()`.
    function protectedSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IKyberMetaAggregationRouterV2Like.swap.selector;
        selectors[1] = IKyberMetaAggregationRouterV2Like.swapGeneric.selector;
        selectors[2] = IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector;
    }

    function _usesProRatedMinimum(bytes4 selector, SwapDescriptionV2 memory desc)
        internal
        pure
        override
        returns (bool)
    {
        if (!_flagsChecked(desc.flags, PARTIAL_FILL)) {
            return false;
        }
        if (selector == IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector) {
            return true;
        }
        if (selector == IKyberMetaAggregationRouterV2Like.swap.selector) {
            return desc.srcToken == ETH_SENTINEL || _flagsChecked(desc.flags, SIMPLE_SWAP);
        }
        return selector == IKyberMetaAggregationRouterV2Like.swapGeneric.selector
            && (desc.srcToken == ETH_SENTINEL || _flagsChecked(desc.flags, SHOULD_CLAIM));
    }
}

/// @title KyberModernMetaAggregationRouterAssertion
/// @notice Assertion artifact for the verified modern router family without `swapGeneric`.
/// @dev Modern-family bit zero has no partial-fill meaning, so it never disables the flat check.
contract KyberModernMetaAggregationRouterAssertion is KyberMetaAggregationRouterAssertionBase {
    constructor(address router_) KyberMetaAggregationRouterAssertionBase(router_) {}

    /// @notice Registers only the verified modern-family settlement entry points.
    function triggers() external view override {
        _registerTriggers(protectedSelectors());
    }

    /// @notice Returns the selector manifest consumed directly by `triggers()`.
    function protectedSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IKyberMetaAggregationRouterV2Like.swap.selector;
        selectors[1] = IKyberMetaAggregationRouterV2Like.swapSimpleMode.selector;
    }

    function _usesProRatedMinimum(bytes4, SwapDescriptionV2 memory) internal pure override returns (bool) {
        return false;
    }
}
