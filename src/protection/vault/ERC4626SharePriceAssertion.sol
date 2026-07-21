// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {IERC4626} from "./IERC4626.sol";
import {ERC4626BaseAssertion} from "./ERC4626BaseAssertion.sol";

/// @title ERC4626SharePriceAssertion
/// @author Phylax Systems
/// @notice Asserts that the vault's share price (totalAssets / totalSupply) does not decrease
///         beyond a configurable tolerance, both transaction-wide and per individual user operation.
///
/// Invariants covered:
///   - **Non-dilutive entry/exit**: absent explicit fee accrual or loss recognition,
///     deposit/mint/withdraw/redeem must not reduce assets-per-share for remaining holders.
///   - **Rounding favors incumbents**: the share price must not move against the vault
///     (i.e., existing holders) during ordinary user operations.
///
/// @dev Uses the V2 `assetsMatchSharePrice` / `assetsMatchSharePriceAt` precompiles for the
///      primary check, and `ratioGe` for an explicit cross-multiplication comparison as a
///      second, readable signal.
///
///      The tolerance is expressed in basis points (1 bps = 0.01%).
///      A tolerance of 0 enforces strict non-decrease; values like 25-50 allow for rounding noise.
abstract contract ERC4626SharePriceAssertion is ERC4626BaseAssertion {
    /// @notice Maximum acceptable share-price decrease in basis points.
    uint256 public immutable sharePriceToleranceBps;

    constructor(uint256 _toleranceBps) {
        sharePriceToleranceBps = _toleranceBps;
    }

    /// @notice Register the default trigger set: the exhaustive tx-wide envelope + per-call checks.
    /// @dev The tx-wide envelope (`assertSharePriceEnvelope`) uses the all-fork-points
    ///      `assetsMatchSharePrice` scan, which re-reads `totalAssets()`/`totalSupply()` at
    ///      ~1+2*callFrames fork points. This is fine for vaults with a cheap `totalAssets()`.
    ///      Vaults with an expensive computed `totalAssets()` (e.g. MetaMorpho, which loops the
    ///      Morpho Blue supply queue) should instead use `_registerBoundedSharePriceTriggers()`:
    ///      the exhaustive scan can exhaust the assertion gas limit on unrelated high-call-count
    ///      transactions that merely touch the vault and revert (PrecompileOOG) — a false invalidation.
    function _registerSharePriceTriggers() internal view {
        registerTxEndTrigger(this.assertSharePriceEnvelope.selector);
        _registerPerCallSharePriceTriggers();
    }

    /// @notice Register a gas-bounded trigger set: a pre/post tx-wide envelope + per-call checks.
    /// @dev The tx-wide check (`assertSharePriceEnvelopeBounded`) compares share price only between
    ///      the pre-tx and post-tx forks — 2 fork points, O(1) in call-frame count — so it never
    ///      triggers the all-forks scan that OOGs on expensive-`totalAssets()` vaults. It is
    ///      two-sided: it catches both dilution (share price down) and unexpected inflation (share
    ///      price up, e.g. a donation / direct-transfer manipulation) reached through ANY entrypoint,
    ///      including non-ERC-4626 selectors the per-call check never observes.
    function _registerBoundedSharePriceTriggers() internal view {
        registerTxEndTrigger(this.assertSharePriceEnvelopeBounded.selector);
        _registerPerCallSharePriceTriggers();
    }

    /// @notice Register only the per-call share-price checks (deposit/mint/withdraw/redeem).
    /// @dev Each fires once per matching ERC-4626 operation and uses the cheap 2-fork
    ///      `assetsMatchSharePriceAt` around that call.
    function _registerPerCallSharePriceTriggers() internal view {
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.deposit.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.mint.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.withdraw.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.redeem.selector);
    }

    // ---------------------------------------------------------------
    //  Tx-wide share-price envelope
    // ---------------------------------------------------------------

    /// @notice Verifies the share price did not decrease beyond tolerance across the entire transaction.
    /// @dev Uses assetsMatchSharePrice for a comprehensive all-forks check, then ratioGe for
    ///      an explicit pre/post comparison as a second signal.
    function assertSharePriceEnvelope() external {
        // Primary check: share price consistent across ALL fork points in the tx
        require(ph.assetsMatchSharePrice(vault, sharePriceToleranceBps), "ERC4626: share price drift exceeds tolerance");

        // Secondary signal: explicit pre/post ratio comparison
        uint256 preAssets = _totalAssetsAt(_preTx());
        uint256 preShares = _totalSupplyAt(_preTx());
        uint256 postAssets = _totalAssetsAt(_postTx());
        uint256 postShares = _totalSupplyAt(_postTx());

        if (preShares == 0 || postShares == 0) return;

        require(
            ph.ratioGe(postAssets, postShares, preAssets, preShares, sharePriceToleranceBps),
            "ERC4626: share price decreased beyond tolerance"
        );
    }

    /// @notice Tx-wide share-price envelope bounded to the pre-tx vs post-tx comparison.
    /// @dev Two-sided within tolerance — catches both dilution (decrease) and unexpected inflation
    ///      (increase, e.g. a donation / direct-transfer share-price manipulation), regardless of the
    ///      entrypoint used. Evaluated at exactly two fork points via `assetsMatchSharePriceAt`, so it
    ///      stays within the assertion gas budget even for vaults with an expensive computed
    ///      `totalAssets()`. Unlike `assertSharePriceEnvelope`, it does not inspect intermediate
    ///      call-boundary forks; the per-call checks cover settlement during standard ERC-4626 ops.
    function assertSharePriceEnvelopeBounded() external {
        require(
            ph.assetsMatchSharePriceAt(vault, sharePriceToleranceBps, _preTx(), _postTx()),
            "ERC4626: tx-wide share price drift exceeds tolerance"
        );
    }

    // ---------------------------------------------------------------
    //  Per-call share-price check
    // ---------------------------------------------------------------

    /// @notice Verifies each individual deposit/mint/withdraw/redeem call does not decrease
    ///         the share price beyond tolerance.
    /// @dev Uses ph.context() to get the triggering call boundaries and
    ///      assetsMatchSharePriceAt for a targeted pre/post-call comparison.
    function assertPerCallSharePrice() external {
        PhEvm.TriggerContext memory ctx = ph.context();

        require(
            ph.assetsMatchSharePriceAt(vault, sharePriceToleranceBps, _preCall(ctx.callStart), _postCall(ctx.callEnd)),
            "ERC4626: call-level share price drift exceeds tolerance"
        );
    }
}
