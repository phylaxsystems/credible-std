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
/// @dev In addition to return values, every operation proves the corresponding receiver/owner
///      share delta, total-supply delta, and underlying-token movement. ERC-4626 does not define a
///      universal preview-distance bound, so every concrete supported adapter must provide one.
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
    /// @dev Must be derived from the concrete vault implementation; no generic default is sound.
    function _maxPreviewDeviation() internal view virtual returns (uint256);

    /// @notice Account whose underlying-token balance reflects ERC-4626 payments and payouts.
    /// @dev Standard vaults custody assets themselves. Managed-custody adapters such as
    ///      LlamaLend must override this with the controller that actually receives and sends the
    ///      underlying token.
    function _assetCustodyAccount() internal view virtual returns (address) {
        return vault;
    }

    // ---------------------------------------------------------------
    //  deposit: previewDeposit(assets) <= actualSharesMinted
    // ---------------------------------------------------------------

    /// @notice For the triggering deposit(assets, receiver) call, verifies:
    ///         previewDeposit(assets) <= actualSharesMinted  (ERC-4626 spec)
    ///         actualSharesMinted - previewDeposit(assets) <= maxDeviation
    function assertDepositPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);
        _requireVaultConfigurationAt(pre);

        bytes memory input = ph.callinputAt(ctx.callStart);
        uint256 assets = _firstUint256Arg(input);
        address receiver = _receiver(input, ctx);
        address payer = _triggerCaller(ctx);

        // Preview at pre-call state
        uint256 previewShares = _readUintAt(vault, abi.encodeCall(IERC4626.previewDeposit, (assets)), pre);

        // Actual return value: deposit returns shares minted
        uint256 actualShares = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewShares <= actualShares, "ERC4626: previewDeposit > actual shares");
        require(actualShares - previewShares <= _maxPreviewDeviation(), "ERC4626: deposit preview deviates from actual");
        _requireIncrease(
            _shareBalanceAt(receiver, pre),
            _shareBalanceAt(receiver, post),
            actualShares,
            "ERC4626: deposit receiver shares mismatch"
        );
        _requireIncrease(_totalSupplyAt(pre), _totalSupplyAt(post), actualShares, "ERC4626: deposit supply mismatch");
        _requirePaymentEffects(payer, _assetCustodyAccount(), assets, pre, post, "deposit");
    }

    // ---------------------------------------------------------------
    //  mint: previewMint(shares) >= actualAssetsCharged
    // ---------------------------------------------------------------

    /// @notice For the triggering mint(shares, receiver) call, verifies:
    ///         previewMint(shares) >= actualAssetsCharged  (ERC-4626 spec)
    ///         previewMint(shares) - actualAssetsCharged <= maxDeviation
    function assertMintPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);
        _requireVaultConfigurationAt(pre);

        bytes memory input = ph.callinputAt(ctx.callStart);
        uint256 shares = _firstUint256Arg(input);
        address receiver = _receiver(input, ctx);
        address payer = _triggerCaller(ctx);

        uint256 previewAssets = _readUintAt(vault, abi.encodeCall(IERC4626.previewMint, (shares)), pre);

        // Actual return value: mint returns assets charged
        uint256 actualAssets = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewAssets >= actualAssets, "ERC4626: previewMint < actual assets");
        require(previewAssets - actualAssets <= _maxPreviewDeviation(), "ERC4626: mint preview deviates from actual");
        _requireIncrease(
            _shareBalanceAt(receiver, pre),
            _shareBalanceAt(receiver, post),
            shares,
            "ERC4626: mint receiver shares mismatch"
        );
        _requireIncrease(_totalSupplyAt(pre), _totalSupplyAt(post), shares, "ERC4626: mint supply mismatch");
        _requirePaymentEffects(payer, _assetCustodyAccount(), actualAssets, pre, post, "mint");
    }

    // ---------------------------------------------------------------
    //  withdraw: previewWithdraw(assets) >= actualSharesBurned
    // ---------------------------------------------------------------

    /// @notice For the triggering withdraw(assets, receiver, owner) call, verifies:
    ///         previewWithdraw(assets) >= actualSharesBurned  (ERC-4626 spec)
    ///         previewWithdraw(assets) - actualSharesBurned <= maxDeviation
    function assertWithdrawPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);
        _requireVaultConfigurationAt(pre);

        bytes memory input = ph.callinputAt(ctx.callStart);
        uint256 assets = _firstUint256Arg(input);
        (address receiver, address owner) = _withdrawAccounts(input, ctx);

        uint256 previewShares = _readUintAt(vault, abi.encodeCall(IERC4626.previewWithdraw, (assets)), pre);

        // Actual return value: withdraw returns shares burned
        uint256 actualShares = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewShares >= actualShares, "ERC4626: previewWithdraw < actual shares");
        require(
            previewShares - actualShares <= _maxPreviewDeviation(), "ERC4626: withdraw preview deviates from actual"
        );
        _requireDecrease(
            _shareBalanceAt(owner, pre),
            _shareBalanceAt(owner, post),
            actualShares,
            "ERC4626: withdraw owner shares mismatch"
        );
        _requireDecrease(_totalSupplyAt(pre), _totalSupplyAt(post), actualShares, "ERC4626: withdraw supply mismatch");
        _requirePayoutEffects(_assetCustodyAccount(), receiver, assets, pre, post, "withdraw");
    }

    // ---------------------------------------------------------------
    //  redeem: previewRedeem(shares) <= actualAssetsReturned
    // ---------------------------------------------------------------

    /// @notice For the triggering redeem(shares, receiver, owner) call, verifies:
    ///         previewRedeem(shares) <= actualAssetsReturned  (ERC-4626 spec)
    ///         actualAssetsReturned - previewRedeem(shares) <= maxDeviation
    function assertRedeemPreview() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);
        _requireVaultConfigurationAt(pre);

        bytes memory input = ph.callinputAt(ctx.callStart);
        uint256 shares = _firstUint256Arg(input);
        (address receiver, address owner) = _withdrawAccounts(input, ctx);

        uint256 previewAssets = _readUintAt(vault, abi.encodeCall(IERC4626.previewRedeem, (shares)), pre);

        // Actual return value: redeem returns assets returned
        uint256 actualAssets = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        require(previewAssets <= actualAssets, "ERC4626: previewRedeem > actual assets");
        require(actualAssets - previewAssets <= _maxPreviewDeviation(), "ERC4626: redeem preview deviates from actual");
        _requireDecrease(
            _shareBalanceAt(owner, pre), _shareBalanceAt(owner, post), shares, "ERC4626: redeem owner shares mismatch"
        );
        _requireDecrease(_totalSupplyAt(pre), _totalSupplyAt(post), shares, "ERC4626: redeem supply mismatch");
        _requirePayoutEffects(_assetCustodyAccount(), receiver, actualAssets, pre, post, "redeem");
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

    /// @notice Reads the first ABI argument from selector-prefixed calldata.
    /// @dev This also supports ERC-4626-compatible default-argument overloads whose first amount
    ///      has the same ABI position as the canonical methods.
    function _firstUint256Arg(bytes memory input) internal pure returns (uint256 value) {
        require(input.length >= 36, "ERC4626Preview: input too short");
        assembly ("memory-safe") {
            value := mload(add(input, 36))
        }
    }

    function _receiver(bytes memory input, PhEvm.TriggerContext memory ctx) internal view returns (address) {
        return input.length >= 68 ? _addressArg(input, 1) : _triggerCaller(ctx);
    }

    function _withdrawAccounts(bytes memory input, PhEvm.TriggerContext memory ctx)
        internal
        view
        returns (address receiver, address owner)
    {
        if (input.length >= 100) return (_addressArg(input, 1), _addressArg(input, 2));
        address caller = _triggerCaller(ctx);
        receiver = input.length >= 68 ? _addressArg(input, 1) : caller;
        owner = caller;
    }

    function _triggerCaller(PhEvm.TriggerContext memory ctx) internal view returns (address) {
        PhEvm.CallFilter memory filter = PhEvm.CallFilter({
            callType: 0, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: true
        });
        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(vault, ctx.selector, filter, 8);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].callId == ctx.callStart) return calls[i].caller;
        }
        revert("ERC4626: triggered call not found");
    }

    function _requirePaymentEffects(
        address payer,
        address custody,
        uint256 amount,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post,
        string memory operation
    ) internal view {
        uint256 payerBefore = _assetBalanceAt(payer, pre);
        uint256 payerAfter = _assetBalanceAt(payer, post);
        if (payer == custody) {
            require(payerAfter == payerBefore, string.concat("ERC4626: ", operation, " asset payment mismatch"));
            return;
        }
        _requireIncrease(
            _assetBalanceAt(custody, pre),
            _assetBalanceAt(custody, post),
            amount,
            string.concat("ERC4626: ", operation, " asset payment mismatch")
        );
        _requireDecrease(
            payerBefore,
            payerAfter,
            amount,
            string.concat("ERC4626: ", operation, " payer assets mismatch")
        );
    }

    function _requirePayoutEffects(
        address custody,
        address receiver,
        uint256 amount,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post,
        string memory operation
    ) internal view {
        uint256 custodyBefore = _assetBalanceAt(custody, pre);
        uint256 custodyAfter = _assetBalanceAt(custody, post);
        if (custody == receiver) {
            require(custodyAfter == custodyBefore, string.concat("ERC4626: ", operation, " asset payout mismatch"));
            return;
        }
        _requireDecrease(
            custodyBefore,
            custodyAfter,
            amount,
            string.concat("ERC4626: ", operation, " vault assets mismatch")
        );
        _requireIncrease(
            _assetBalanceAt(receiver, pre),
            _assetBalanceAt(receiver, post),
            amount,
            string.concat("ERC4626: ", operation, " receiver assets mismatch")
        );
    }

    function _addressArg(bytes memory input, uint256 index) internal pure returns (address value) {
        uint256 offset = 36 + index * 32;
        require(input.length >= 4 + (index + 1) * 32, "ERC4626Preview: address arg missing");
        assembly ("memory-safe") {
            value := mload(add(input, offset))
        }
    }

    function _requireIncrease(uint256 beforeValue, uint256 afterValue, uint256 amount, string memory reason)
        internal
        pure
    {
        require(afterValue >= beforeValue && afterValue - beforeValue == amount, reason);
    }

    function _requireDecrease(uint256 beforeValue, uint256 afterValue, uint256 amount, string memory reason)
        internal
        pure
    {
        require(beforeValue >= afterValue && beforeValue - afterValue == amount, reason);
    }
}
