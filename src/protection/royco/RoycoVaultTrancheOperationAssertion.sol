// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {IRoycoVaultTranche, RoycoAssetClaims, RoycoVaultTrancheHelpers} from "./RoycoHelpers.sol";

/// @title RoycoVaultTrancheOperationAssertion
/// @author Phylax Systems
/// @notice Tranche-side Royco invariant checks for preview consistency, protocol-fee share
///         minting, virtual offset share math, and redeem-before-burn ordering.
abstract contract RoycoVaultTrancheOperationAssertion is RoycoVaultTrancheHelpers {
    /// @notice Registers the default deposit/redeem invariant set for a Royco tranche.
    function _registerOperationInvariantTriggers() internal view {
        registerFnCallTrigger(this.assertDepositPreviewConsistency.selector, IRoycoVaultTranche.deposit.selector);
        registerFnCallTrigger(this.assertRedeemPreviewConsistency.selector, IRoycoVaultTranche.redeem.selector);
        registerFnCallTrigger(this.assertRedeemOrdering.selector, IRoycoVaultTranche.redeem.selector);
    }

    /// @notice Previewed deposits must match actual user share minting, protocol-fee share
    ///         issuance, and the tranche's one-share/one-wei virtual offset formula.
    function assertDepositPreviewConsistency() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory postFork = _postCall(ctx.callEnd);

        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 assets_,) = _decodeTrancheDepositInput(input);

        uint256 expectedUserShares = _previewDepositAt(assets_, preFork);
        uint256 actualUserShares = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));
        require(actualUserShares == expectedUserShares, "Royco: deposit preview mismatch");

        uint256 preSupply = _totalSupplyAt(preFork);
        uint256 postSupply = _totalSupplyAt(postFork);
        require(postSupply >= preSupply + actualUserShares, "Royco: deposit supply delta mismatch");

        uint256 actualFeeSharesMinted = postSupply - preSupply - actualUserShares;
        (uint256 expectedFeeSharesMinted, uint256 expectedFormulaShares) =
            _expectedDepositMathAt(assets_, preFork, preSupply);
        require(actualFeeSharesMinted == expectedFeeSharesMinted, "Royco: protocol fee share mint mismatch");
        require(
            actualUserShares == expectedFormulaShares, "Royco: deposit share math drifted from virtual offset formula"
        );
    }

    /// @notice Previewed redemptions must match the actual claim bundle returned to the caller.
    function assertRedeemPreviewConsistency() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preFork = _preCall(ctx.callStart);

        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 shares,,) = _decodeTrancheRedeemInput(input);

        RoycoAssetClaims memory previewClaims = _previewRedeemAt(shares, preFork);
        RoycoAssetClaims memory actualClaims = abi.decode(ph.callOutputAt(ctx.callStart), (RoycoAssetClaims));

        require(actualClaims.stAssets == previewClaims.stAssets, "Royco: redeem ST asset preview mismatch");
        require(actualClaims.jtAssets == previewClaims.jtAssets, "Royco: redeem JT asset preview mismatch");
        require(actualClaims.nav == previewClaims.nav, "Royco: redeem NAV preview mismatch");
    }

    /// @notice The tranche must enter the kernel redeem path before its own share burn executes.
    /// @dev The kernel depends on pre-burn supply when scaling claims and fee-share dilution. The
    ///      matching logic intentionally scopes kernel calls to the outer redeem frame to catch
    ///      accidental duplicate redeem paths inside the same call.
    function assertRedeemOrdering() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 shares, address receiver,) = _decodeTrancheRedeemInput(input);

        PhEvm.TriggerCall memory kernelRedeemCall = _resolveTriggeredKernelRedeemCall(ctx, shares, receiver);
        uint256 preRedeemSupply = _totalSupplyAt(_preCall(ctx.callStart));
        uint256 supplyAtKernelEntry = _totalSupplyAt(_preCall(kernelRedeemCall.callId));

        require(supplyAtKernelEntry == preRedeemSupply, "Royco: redeem burned shares before kernel call");
    }
}
