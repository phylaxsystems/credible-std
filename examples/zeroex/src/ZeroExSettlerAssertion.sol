// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {ZeroExSettlerHelpers} from "./ZeroExSettlerHelpers.sol";
import {
    IZeroExSettlerLike,
    IZeroExSettlerMetaTxnLike,
    ZeroExSettlerSlippage
} from "./ZeroExSettlerInterfaces.sol";

/// @title ZeroExSettlerAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for 0x Settler deployments.
/// @dev Protects router-level settlement invariants that are awkward or expensive to enforce in
///      every production call:
///      - live executions must target the registry current or previous Settler for the feature;
///      - ERC20 buy-token settlements must increase the declared recipient balance by at least
///        the signed minimum output, catching fee-on-transfer or malicious-token edge cases.
/// @dev Transfer events do not identify the spender that moved a token. The legacy allowance
///      heuristic remains callable for compatibility, but is deliberately not registered.
contract ZeroExSettlerAssertion is ZeroExSettlerHelpers {
    constructor(address settler_, address registry_, uint128 featureId_)
        ZeroExSettlerHelpers(settler_, registry_, featureId_)
    {}

    /// @notice Registers all supported 0x Settler settlement entry points.
    /// @dev Each assertion uses call-scoped fork reads so checks are bound to the exact execution
    ///      that the adopter accepted.
    function triggers() external view override {
        registerFnCallTrigger(this.assertSettlerRegistered.selector, IZeroExSettlerLike.execute.selector);
        registerFnCallTrigger(this.assertSettlerRegistered.selector, IZeroExSettlerLike.executeWithPermit.selector);
        registerFnCallTrigger(this.assertSettlerRegistered.selector, IZeroExSettlerMetaTxnLike.executeMetaTxn.selector);

        registerFnCallTrigger(
            this.assertRecipientReceivesMinimumBuyAmount.selector, IZeroExSettlerLike.execute.selector
        );
        registerFnCallTrigger(
            this.assertRecipientReceivesMinimumBuyAmount.selector, IZeroExSettlerLike.executeWithPermit.selector
        );
        registerFnCallTrigger(
            this.assertRecipientReceivesMinimumBuyAmount.selector, IZeroExSettlerMetaTxnLike.executeMetaTxn.selector
        );

    }

    /// @notice A called Settler must still be the registry's current or previous deployment.
    /// @dev 0x integrations are expected to resolve Settler through the deployer/registry because
    ///      old instances can be removed or paused. A failure means the transaction used a router
    ///      address that the registry no longer recognizes for the configured feature.
    function assertSettlerRegistered() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredSettlerIsAdopter();
        _requireRegisteredSettlerAt(_preCall(ctx.callStart));
        _requireRegisteredSettlerAt(_postCall(ctx.callEnd));
    }

    /// @notice ERC20 settlement must credit the declared recipient by at least `minAmountOut`.
    /// @dev Settler checks its own token balance before transferring, but only a fork-aware
    ///      recipient balance comparison can catch tokens whose transfer succeeds while crediting
    ///      less than the user-signed minimum. Native ETH payouts are intentionally out of scope
    ///      because this assertion surface currently reads ERC20 balances only.
    function assertRecipientReceivesMinimumBuyAmount() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredSettlerIsAdopter();

        ZeroExSettlerSlippage memory slippage = _slippageFromCallInput(ph.callinputAt(ctx.callStart));
        if (slippage.minAmountOut == 0 || slippage.buyToken == ETH_SENTINEL) {
            return;
        }

        uint256 beforeBalance = _readBalanceAt(slippage.buyToken, slippage.recipient, _preCall(ctx.callStart));
        uint256 afterBalance = _readBalanceAt(slippage.buyToken, slippage.recipient, _postCall(ctx.callEnd));

        require(afterBalance >= beforeBalance, "0xSettler: recipient balance decreased");
        require(afterBalance - beforeBalance >= slippage.minAmountOut, "0xSettler: recipient credited below minimum");
    }

    /// @notice Legacy diagnostic retained for source compatibility; it is not registered.
    /// @dev Transfer logs cannot establish that Settler was the allowance spender.
    function assertNoPreApprovedTransferSource() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredSettlerIsAdopter();
        _assertNoPreCallAllowanceForTransferLogs(ctx.callStart);
    }
}
