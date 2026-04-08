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

    /// @notice Register the default trigger set for share-price invariants.
    /// @dev Uses registerTxEndTrigger for the tx-wide envelope and registerFnCallTrigger
    ///      for per-call checks. Call this inside your `triggers()`.
    function _registerSharePriceTriggers() internal view {
        // Tx-wide envelope — fires once after the transaction completes
        registerTxEndTrigger(this.assertSharePriceEnvelope.selector);

        // Per-call check — fires once per matching ERC-4626 operation
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
