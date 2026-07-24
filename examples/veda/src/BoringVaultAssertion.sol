// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {BoringVaultHelpers} from "./BoringVaultHelpers.sol";
import {IBoringVaultLike} from "./BoringVaultInterfaces.sol";

/// @title BoringVaultAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for Veda Boring Vault deployments.
/// @dev Intended to be applied to the BoringVault contract, not the Teller.
///
///      The bundle focuses on a small set of high-signal protections:
///      - `enter` cannot mint shares beyond the accountant value of the asset entering
///        the vault, and the share/token deltas must match the call arguments.
///      - `exit` must burn exactly the requested shares and move exactly the requested
///        asset amount out of vault custody.
///      - canonical zero-asset remediation, bridge, and migration calls conserve shares and are
///        accepted only from explicitly configured callers.
///
///      This bundle supports standard non-rebasing ERC-20 assets. Rolling idle-balance flow
///      breakers were removed: net Transfer-log flow is neither portfolio TVL nor gross exits and
///      rejects valid strategy deployment and empty-vault initialization.
contract BoringVaultAssertion is BoringVaultHelpers {
    /// @notice Constructor value that disables the exit price-bound check.
    uint256 public constant DISABLE_EXIT_RATE_BOUND = type(uint256).max;

    /// @notice Extra share mint tolerance above accountant pricing. 100 = 1%.
    uint256 public immutable maxShareMintPremiumBps;

    /// @notice Extra asset-out tolerance above accountant pricing. 100 = 1%.
    /// @dev Set to `DISABLE_EXIT_RATE_BOUND` to support refund flows that intentionally
    ///      return original assets while still enforcing exact burn/custody accounting.
    uint256 public immutable maxExitAssetsPremiumBps;

    mapping(address caller => bool allowed) public shareOnlyCaller;

    constructor(
        address vault_,
        address accountant_,
        uint8 vaultDecimals_,
        address[] memory shareOnlyCallers_,
        uint256 maxShareMintPremiumBps_,
        uint256 maxExitAssetsPremiumBps_
    ) BoringVaultHelpers(vault_, accountant_, vaultDecimals_) {
        require(maxShareMintPremiumBps_ <= 10_000, "BoringVault: mint premium too large");
        require(
            maxExitAssetsPremiumBps_ == DISABLE_EXIT_RATE_BOUND || maxExitAssetsPremiumBps_ <= 10_000,
            "BoringVault: exit premium too large"
        );
        maxShareMintPremiumBps = maxShareMintPremiumBps_;
        maxExitAssetsPremiumBps = maxExitAssetsPremiumBps_;

        for (uint256 i; i < shareOnlyCallers_.length; ++i) {
            address caller = shareOnlyCallers_[i];
            require(caller != address(0), "BoringVault: zero share-only caller");
            require(!shareOnlyCaller[caller], "BoringVault: duplicate share-only caller");
            shareOnlyCaller[caller] = true;
        }

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires call-scoped accounting checks.
    function triggers() external view override {
        registerFnCallTrigger(this.assertEnterAccounting.selector, IBoringVaultLike.enter.selector);
        registerFnCallTrigger(this.assertExitAccounting.selector, IBoringVaultLike.exit.selector);
    }

    /// @notice Checks that a BoringVault `enter` call is collateralized and share accounting is exact.
    /// @dev The trigger is the vault's `enter(from, asset, assetAmount, to, shareAmount)`.
    ///      A failure means the minter minted too many shares for the accountant rate, minted
    ///      without the advertised asset inflow, or changed supply/balances inconsistently.
    function assertEnterAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        (, address asset, uint256 assetAmount, address to, uint256 shareAmount) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, address, uint256, address, uint256));

        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        _requireConfigurationAt(beforeFork);

        uint256 preSupply = _totalSupplyAt(beforeFork);
        uint256 postSupply = _totalSupplyAt(afterFork);
        uint256 preReceiverShares = _shareBalanceAt(to, beforeFork);
        uint256 postReceiverShares = _shareBalanceAt(to, afterFork);
        require(postSupply == preSupply + shareAmount, "BoringVault: enter supply delta mismatch");
        require(postReceiverShares == preReceiverShares + shareAmount, "BoringVault: enter share delta mismatch");

        if (assetAmount == 0) {
            require(asset == address(0), "BoringVault: nonzero asset on share-only enter");
            _requireShareOnlyCaller(ctx);
            return;
        }
        require(asset != address(0), "BoringVault: zero asset");

        uint256 preVaultAssets = _assetBalanceAt(asset, vault, beforeFork);
        uint256 postVaultAssets = _assetBalanceAt(asset, vault, afterFork);
        require(postVaultAssets == preVaultAssets + assetAmount, "BoringVault: enter asset delta mismatch");

        uint256 maxShares = _maxSharesForDepositAt(asset, assetAmount, beforeFork);
        uint256 maxSharesWithTolerance = maxShares + ph.mulDivUp(maxShares, maxShareMintPremiumBps, 10_000);
        require(shareAmount <= maxSharesWithTolerance, "BoringVault: enter over-minted shares");
    }

    /// @notice Checks that a BoringVault `exit` call burns shares and moves assets consistently.
    /// @dev The trigger is the vault's `exit(to, asset, assetAmount, from, shareAmount)`.
    ///      A failure means the burner extracted too many assets for the burned shares or
    ///      custody/share balances did not move exactly as the vault event arguments claim.
    function assertExitAccounting() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        (address to, address asset, uint256 assetAmount, address from, uint256 shareAmount) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, address, uint256, address, uint256));

        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        _requireConfigurationAt(beforeFork);

        uint256 preSupply = _totalSupplyAt(beforeFork);
        uint256 postSupply = _totalSupplyAt(afterFork);
        uint256 preOwnerShares = _shareBalanceAt(from, beforeFork);
        uint256 postOwnerShares = _shareBalanceAt(from, afterFork);
        require(preSupply >= shareAmount, "BoringVault: exit burns too many shares");
        require(preOwnerShares >= shareAmount, "BoringVault: exit owner share underflow");
        require(postSupply == preSupply - shareAmount, "BoringVault: exit supply delta mismatch");
        require(postOwnerShares == preOwnerShares - shareAmount, "BoringVault: exit share delta mismatch");

        if (asset == address(0)) {
            require(assetAmount == 0, "BoringVault: nonzero amount on share-only exit");
            _requireShareOnlyCaller(ctx);
            return;
        }

        uint256 preVaultAssets = _assetBalanceAt(asset, vault, beforeFork);
        uint256 postVaultAssets = _assetBalanceAt(asset, vault, afterFork);
        uint256 preRecipientAssets = _assetBalanceAt(asset, to, beforeFork);
        uint256 postRecipientAssets = _assetBalanceAt(asset, to, afterFork);
        require(preVaultAssets >= assetAmount, "BoringVault: exit asset underflow");
        require(postVaultAssets == preVaultAssets - assetAmount, "BoringVault: exit asset delta mismatch");
        require(postRecipientAssets == preRecipientAssets + assetAmount, "BoringVault: exit recipient underpaid");

        if (maxExitAssetsPremiumBps != DISABLE_EXIT_RATE_BOUND) {
            uint256 maxAssets = _maxAssetsForExitAt(asset, shareAmount, beforeFork);
            uint256 maxAssetsWithTolerance = maxAssets + ph.mulDivUp(maxAssets, maxExitAssetsPremiumBps, 10_000);
            require(assetAmount <= maxAssetsWithTolerance, "BoringVault: exit overpaid assets");
        }
    }

    function _requireShareOnlyCaller(PhEvm.TriggerContext memory ctx) internal view {
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(vault, ctx.selector);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == ctx.callStart) {
                require(shareOnlyCaller[calls[i].caller], "BoringVault: unauthorized share-only caller");
                return;
            }
        }
        revert("BoringVault: triggered call not found");
    }
}
