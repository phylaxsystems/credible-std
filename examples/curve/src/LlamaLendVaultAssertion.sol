// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {ERC4626BaseAssertion} from "credible-std/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626PreviewAssertion} from "credible-std/protection/vault/ERC4626PreviewAssertion.sol";
import {LlamaLendVaultProtocolHelpers} from "./LlamaLendProtocol.sol";

/// @title LlamaLendVaultAssertion
/// @notice Example LlamaLend vault checks for controller-backed accounting and borrowed-token custody.
contract LlamaLendVaultAssertion is ERC4626PreviewAssertion, LlamaLendVaultProtocolHelpers {
    bytes4 internal constant DEPOSIT_DEFAULT = bytes4(keccak256("deposit(uint256)"));
    bytes4 internal constant MINT_DEFAULT = bytes4(keccak256("mint(uint256)"));
    bytes4 internal constant WITHDRAW_DEFAULT = bytes4(keccak256("withdraw(uint256)"));
    bytes4 internal constant WITHDRAW_RECEIVER = bytes4(keccak256("withdraw(uint256,address)"));
    bytes4 internal constant REDEEM_DEFAULT = bytes4(keccak256("redeem(uint256)"));
    bytes4 internal constant REDEEM_RECEIVER = bytes4(keccak256("redeem(uint256,address)"));

    constructor(address vault_, address asset_, address controller_)
        ERC4626BaseAssertion(vault_, asset_)
        LlamaLendVaultProtocolHelpers(controller_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers preview checks plus controller-side accounting and custody checks.
    function triggers() external view override {
        _registerPreviewTriggers();
        registerFnCallTrigger(this.assertDepositPreview.selector, DEPOSIT_DEFAULT);
        registerFnCallTrigger(this.assertMintPreview.selector, MINT_DEFAULT);
        registerFnCallTrigger(this.assertWithdrawPreview.selector, WITHDRAW_DEFAULT);
        registerFnCallTrigger(this.assertWithdrawPreview.selector, WITHDRAW_RECEIVER);
        registerFnCallTrigger(this.assertRedeemPreview.selector, REDEEM_DEFAULT);
        registerFnCallTrigger(this.assertRedeemPreview.selector, REDEEM_RECEIVER);
        registerTxEndTrigger(this.assertTotalAssetsMatchesControllerAccounting.selector);
        registerTxEndTrigger(this.assertControllerCustodyCoversAvailableBalance.selector);
    }

    /// @notice Checks `totalAssets()` equals controller available balance plus debt minus admin fees.
    function assertTotalAssetsMatchesControllerAccounting() external {
        PhEvm.ForkId memory fork = _postTx();
        _requireVaultConfigurationAt(fork);
        require(_totalAssetsAt(fork) == _llamaExpectedTotalAssetsAt(fork), "LlamaLend: totalAssets mismatch");
    }

    /// @notice Checks borrowed-token custody at the controller covers `available_balance()`.
    function assertControllerCustodyCoversAvailableBalance() external {
        PhEvm.ForkId memory fork = _postTx();
        _requireVaultConfigurationAt(fork);
        require(
            _llamaControllerAssetBalanceAt(fork) >= _llamaAvailableBalanceAt(fork),
            "LlamaLend: controller custody below available balance"
        );
    }
}
