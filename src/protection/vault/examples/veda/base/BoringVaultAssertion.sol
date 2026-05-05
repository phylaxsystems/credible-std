// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../../PhEvm.sol";

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
///      - cumulative inflow/outflow breakers monitor actual ERC-20 balance deltas of
///        the vault, so they supersede teller-side deposit caps and withdrawal limits
///        by catching direct `enter`/`exit`, `manage`, and other balance-moving paths.
contract BoringVaultAssertion is BoringVaultHelpers {
    /// @notice Constructor value that disables the exit price-bound check.
    uint256 public constant DISABLE_EXIT_RATE_BOUND = type(uint256).max;

    /// @notice Extra share mint tolerance above accountant pricing. 100 = 1%.
    uint256 public immutable maxShareMintPremiumBps;

    /// @notice Extra asset-out tolerance above accountant pricing. 100 = 1%.
    /// @dev Set to `DISABLE_EXIT_RATE_BOUND` to support refund flows that intentionally
    ///      return original assets while still enforcing exact burn/custody accounting.
    uint256 public immutable maxExitAssetsPremiumBps;

    /// @notice Hard cumulative inflow breaker threshold. Zero disables inflow breaker registration.
    uint256 public immutable cumulativeInflowThresholdBps;

    /// @notice Hard cumulative outflow breaker threshold. Zero disables outflow breaker registration.
    uint256 public immutable cumulativeOutflowThresholdBps;

    /// @notice Rolling window, in seconds, used by cumulative flow breakers.
    uint256 public immutable flowWindowDuration;

    /// @notice ERC-20 assets whose vault balance should be protected by hard flow breakers.
    address[] public monitoredAssets;

    constructor(
        address vault_,
        address accountant_,
        uint8 vaultDecimals_,
        address[] memory monitoredAssets_,
        uint256 maxShareMintPremiumBps_,
        uint256 maxExitAssetsPremiumBps_,
        uint256 cumulativeInflowThresholdBps_,
        uint256 cumulativeOutflowThresholdBps_,
        uint256 flowWindowDuration_
    ) BoringVaultHelpers(vault_, accountant_, vaultDecimals_) {
        require(maxShareMintPremiumBps_ <= 10_000, "BoringVault: mint premium too large");
        require(
            maxExitAssetsPremiumBps_ == DISABLE_EXIT_RATE_BOUND || maxExitAssetsPremiumBps_ <= 10_000,
            "BoringVault: exit premium too large"
        );
        require(monitoredAssets_.length > 0, "BoringVault: no monitored assets");
        require(
            flowWindowDuration_ > 0 || (cumulativeInflowThresholdBps_ == 0 && cumulativeOutflowThresholdBps_ == 0),
            "BoringVault: zero flow window"
        );

        maxShareMintPremiumBps = maxShareMintPremiumBps_;
        maxExitAssetsPremiumBps = maxExitAssetsPremiumBps_;
        cumulativeInflowThresholdBps = cumulativeInflowThresholdBps_;
        cumulativeOutflowThresholdBps = cumulativeOutflowThresholdBps_;
        flowWindowDuration = flowWindowDuration_;

        for (uint256 i; i < monitoredAssets_.length; ++i) {
            require(monitoredAssets_[i] != address(0), "BoringVault: zero monitored asset");
            monitoredAssets.push(monitoredAssets_[i]);
        }
    }

    /// @notice Wires call-scoped accounting checks and hard cumulative flow breakers.
    /// @dev `registerFnCallTrigger` catches successful calls to the BoringVault adopter at
    ///      any call depth. The cumulative flow triggers monitor actual token balance deltas
    ///      of the adopter over a rolling window, independent of teller-level limits.
    function triggers() external view override {
        registerFnCallTrigger(this.assertEnterAccounting.selector, IBoringVaultLike.enter.selector);
        registerFnCallTrigger(this.assertExitAccounting.selector, IBoringVaultLike.exit.selector);

        for (uint256 i; i < monitoredAssets.length; ++i) {
            address asset = monitoredAssets[i];
            if (cumulativeInflowThresholdBps > 0) {
                watchCumulativeInflow(
                    asset, cumulativeInflowThresholdBps, flowWindowDuration, this.assertCumulativeInflowBreaker.selector
                );
            }
            if (cumulativeOutflowThresholdBps > 0) {
                watchCumulativeOutflow(
                    asset,
                    cumulativeOutflowThresholdBps,
                    flowWindowDuration,
                    this.assertCumulativeOutflowBreaker.selector
                );
            }
        }
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

        uint256 preSupply = _totalSupplyAt(beforeFork);
        uint256 postSupply = _totalSupplyAt(afterFork);
        uint256 preReceiverShares = _shareBalanceAt(to, beforeFork);
        uint256 postReceiverShares = _shareBalanceAt(to, afterFork);
        uint256 preVaultAssets = _assetBalanceAt(asset, vault, beforeFork);
        uint256 postVaultAssets = _assetBalanceAt(asset, vault, afterFork);

        require(postSupply == preSupply + shareAmount, "BoringVault: enter supply delta mismatch");
        require(postReceiverShares == preReceiverShares + shareAmount, "BoringVault: enter share delta mismatch");
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
        (, address asset, uint256 assetAmount, address from, uint256 shareAmount) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, address, uint256, address, uint256));

        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);

        uint256 preSupply = _totalSupplyAt(beforeFork);
        uint256 postSupply = _totalSupplyAt(afterFork);
        uint256 preOwnerShares = _shareBalanceAt(from, beforeFork);
        uint256 postOwnerShares = _shareBalanceAt(from, afterFork);
        uint256 preVaultAssets = _assetBalanceAt(asset, vault, beforeFork);
        uint256 postVaultAssets = _assetBalanceAt(asset, vault, afterFork);

        require(preSupply >= shareAmount, "BoringVault: exit burns too many shares");
        require(preOwnerShares >= shareAmount, "BoringVault: exit owner share underflow");
        require(preVaultAssets >= assetAmount, "BoringVault: exit asset underflow");
        require(postSupply == preSupply - shareAmount, "BoringVault: exit supply delta mismatch");
        require(postOwnerShares == preOwnerShares - shareAmount, "BoringVault: exit share delta mismatch");
        require(postVaultAssets == preVaultAssets - assetAmount, "BoringVault: exit asset delta mismatch");

        if (maxExitAssetsPremiumBps != DISABLE_EXIT_RATE_BOUND) {
            uint256 maxAssets = _maxAssetsForExitAt(asset, shareAmount, beforeFork);
            uint256 maxAssetsWithTolerance = maxAssets + ph.mulDivUp(maxAssets, maxExitAssetsPremiumBps, 10_000);
            require(assetAmount <= maxAssetsWithTolerance, "BoringVault: exit overpaid assets");
        }
    }

    /// @notice Hard breaker for cumulative token inflows into vault custody.
    /// @dev Fires only after `watchCumulativeInflow` reports a monitored asset breached
    ///      the configured rolling-window threshold. This blocks deposits or manager flows
    ///      that would bypass or overwhelm the teller's share-denominated deposit cap.
    function assertCumulativeInflowBreaker() external pure {
        revert("BoringVault: cumulative inflow breaker tripped");
    }

    /// @notice Hard breaker for cumulative token outflows from vault custody.
    /// @dev Fires only after `watchCumulativeOutflow` reports a monitored asset breached
    ///      the configured rolling-window threshold. This blocks withdrawals, refunds,
    ///      manager calls, or direct balance-moving paths that exceed the external breaker.
    function assertCumulativeOutflowBreaker() external pure {
        revert("BoringVault: cumulative outflow breaker tripped");
    }
}
