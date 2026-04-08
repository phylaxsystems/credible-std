// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {IERC4626} from "./IERC4626.sol";
import {ERC4626BaseAssertion} from "./ERC4626BaseAssertion.sol";

/// @title ERC4626PreviewAssertion
/// @author Phylax Systems
/// @notice Asserts that ERC-4626 preview functions are consistent with the actual results of
///         the corresponding state-changing operations, and that rounding favors the vault.
///
/// Invariants covered:
///   - **Preview consistency**: for the same pre-state,
///       previewDeposit(a)  == shares minted by deposit(a)
///       previewMint(s)     == assets charged by mint(s)
///       previewWithdraw(a) == shares burned by withdraw(a)
///       previewRedeem(s)   == assets returned by redeem(s)
///
///   - **Rounding direction** (implicit in the inequality checks):
///       previewDeposit  rounds DOWN (returns fewer shares  -> favors vault)
///       previewMint     rounds UP   (returns more assets   -> favors vault)
///       previewWithdraw rounds UP   (returns more shares   -> favors vault)
///       previewRedeem   rounds DOWN (returns fewer assets   -> favors vault)
///
/// @dev Uses V2 `registerFnCallTrigger` + `ph.context()` for call-scoped triggers,
///      `ph.callinputAt()` to read call arguments, and `ph.callOutputAt()` to read the
///      actual return value — replacing the totalSupply/totalAssets delta inference from V1.
abstract contract ERC4626PreviewAssertion is ERC4626BaseAssertion {
    /// @notice Register the default trigger set for preview-consistency invariants.
    /// @dev Each ERC-4626 operation gets its own assertion function via registerFnCallTrigger.
    function _registerPreviewTriggers() internal view {
        registerFnCallTrigger(this.assertDepositPreview.selector, IERC4626.deposit.selector);
        registerFnCallTrigger(this.assertMintPreview.selector, IERC4626.mint.selector);
        registerFnCallTrigger(this.assertWithdrawPreview.selector, IERC4626.withdraw.selector);
        registerFnCallTrigger(this.assertRedeemPreview.selector, IERC4626.redeem.selector);
    }

    /// @notice Maximum acceptable deviation between a preview result and the actual result.
    /// @dev Defaults to 1 (single-unit rounding). Override for vaults with wider rounding
    ///      (e.g. multi-step rounding, fee chunking, or decimal normalization).
    function _maxPreviewDeviation() internal view virtual returns (uint256) {
        return 1;
    }

    // ---------------------------------------------------------------
    //  deposit: previewDeposit(assets) <= actualSharesMinted
    // ---------------------------------------------------------------

    /// @notice For the triggering deposit(assets, receiver) call, verifies:
    ///         previewDeposit(assets) <= actualSharesMinted  (ERC-4626 spec)
    ///         actualSharesMinted - previewDeposit(assets) <= maxDeviation
    function assertDepositPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();

        // Decode call input: deposit(uint256 assets, address receiver) → extract assets
        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 assets,) = abi.decode(_stripSelector(input), (uint256, address));

        // Preview at pre-call state
        uint256 previewShares =
            _readUintAt(vault, abi.encodeCall(IERC4626.previewDeposit, (assets)), _preCall(ctx.callStart));

        // Actual return value: deposit returns shares minted
        uint256 actualShares = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewShares <= actualShares, "ERC4626: previewDeposit > actual shares");
        require(actualShares - previewShares <= _maxPreviewDeviation(), "ERC4626: deposit preview deviates from actual");
    }

    // ---------------------------------------------------------------
    //  mint: previewMint(shares) >= actualAssetsCharged
    // ---------------------------------------------------------------

    /// @notice For the triggering mint(shares, receiver) call, verifies:
    ///         previewMint(shares) >= actualAssetsCharged  (ERC-4626 spec)
    ///         previewMint(shares) - actualAssetsCharged <= maxDeviation
    function assertMintPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();

        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 shares,) = abi.decode(_stripSelector(input), (uint256, address));

        uint256 previewAssets =
            _readUintAt(vault, abi.encodeCall(IERC4626.previewMint, (shares)), _preCall(ctx.callStart));

        // Actual return value: mint returns assets charged
        uint256 actualAssets = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewAssets >= actualAssets, "ERC4626: previewMint < actual assets");
        require(previewAssets - actualAssets <= _maxPreviewDeviation(), "ERC4626: mint preview deviates from actual");
    }

    // ---------------------------------------------------------------
    //  withdraw: previewWithdraw(assets) >= actualSharesBurned
    // ---------------------------------------------------------------

    /// @notice For the triggering withdraw(assets, receiver, owner) call, verifies:
    ///         previewWithdraw(assets) >= actualSharesBurned  (ERC-4626 spec)
    ///         previewWithdraw(assets) - actualSharesBurned <= maxDeviation
    function assertWithdrawPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();

        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 assets,,) = abi.decode(_stripSelector(input), (uint256, address, address));

        uint256 previewShares =
            _readUintAt(vault, abi.encodeCall(IERC4626.previewWithdraw, (assets)), _preCall(ctx.callStart));

        // Actual return value: withdraw returns shares burned
        uint256 actualShares = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewShares >= actualShares, "ERC4626: previewWithdraw < actual shares");
        require(
            previewShares - actualShares <= _maxPreviewDeviation(), "ERC4626: withdraw preview deviates from actual"
        );
    }

    // ---------------------------------------------------------------
    //  redeem: previewRedeem(shares) <= actualAssetsReturned
    // ---------------------------------------------------------------

    /// @notice For the triggering redeem(shares, receiver, owner) call, verifies:
    ///         previewRedeem(shares) <= actualAssetsReturned  (ERC-4626 spec)
    ///         actualAssetsReturned - previewRedeem(shares) <= maxDeviation
    function assertRedeemPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();

        bytes memory input = ph.callinputAt(ctx.callStart);
        (uint256 shares,,) = abi.decode(_stripSelector(input), (uint256, address, address));

        uint256 previewAssets =
            _readUintAt(vault, abi.encodeCall(IERC4626.previewRedeem, (shares)), _preCall(ctx.callStart));

        // Actual return value: redeem returns assets returned
        uint256 actualAssets = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewAssets <= actualAssets, "ERC4626: previewRedeem > actual assets");
        require(actualAssets - previewAssets <= _maxPreviewDeviation(), "ERC4626: redeem preview deviates from actual");
    }

    // ---------------------------------------------------------------
    //  Calldata helper
    // ---------------------------------------------------------------

    /// @notice Strip the 4-byte selector from raw call input bytes.
    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "ERC4626Preview: input too short");
        args = new bytes(input.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = input[i + 4];
        }
    }
}
