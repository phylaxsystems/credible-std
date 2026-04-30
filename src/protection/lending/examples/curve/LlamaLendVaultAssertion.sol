// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";
import {ERC4626BaseAssertion} from "../../../vault/ERC4626BaseAssertion.sol";
import {ERC4626PreviewAssertion} from "../../../vault/ERC4626PreviewAssertion.sol";
import {ERC4626SharePriceAssertion} from "../../../vault/ERC4626SharePriceAssertion.sol";
import {LlamaLendVaultProtocolHelpers} from "./LlamaLendProtocol.sol";

/// @title LlamaLendVaultAssertion
/// @notice Example LlamaLend vault checks for controller-backed accounting and borrowed-token custody.
contract LlamaLendVaultAssertion is ERC4626SharePriceAssertion, ERC4626PreviewAssertion, LlamaLendVaultProtocolHelpers {
    constructor(address vault_, uint256 sharePriceToleranceBps_)
        ERC4626BaseAssertion(vault_)
        ERC4626SharePriceAssertion(sharePriceToleranceBps_)
        LlamaLendVaultProtocolHelpers(vault_)
    {}

    /// @notice Registers ERC4626-style checks plus controller-side accounting and custody checks.
    function triggers() external view override {
        _registerSharePriceTriggers();
        _registerPreviewTriggers();
        _registerAssetFlowTriggers();
        registerTxEndTrigger(this.assertTotalAssetsMatchesControllerAccounting.selector);
        registerTxEndTrigger(this.assertControllerCustodyCoversAvailableBalance.selector);
    }

    /// @notice Checks `totalAssets()` equals controller available balance plus debt minus admin fees.
    function assertTotalAssetsMatchesControllerAccounting() external {
        PhEvm.ForkId memory fork = _postTx();
        require(_totalAssetsAt(fork) == _llamaExpectedTotalAssetsAt(fork), "LlamaLend: totalAssets mismatch");
    }

    /// @notice Checks borrowed-token custody at the controller covers `available_balance()`.
    function assertControllerCustodyCoversAvailableBalance() external {
        PhEvm.ForkId memory fork = _postTx();
        require(
            _llamaControllerAssetBalanceAt(fork) >= _llamaAvailableBalanceAt(fork),
            "LlamaLend: controller custody below available balance"
        );
    }
}
