// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {IFTokenLike} from "./FluidInterfaces.sol";

/// @title FluidFTokenSharePriceAssertion
/// @author Phylax Systems
/// @notice fToken (ERC-4626 lending token) share price never decreases across a transaction.
/// @dev Install on an fToken (fUSDC, fWETH, ...), the assertion adopter. An fToken supplies all of
///      its underlying into the Liquidity Layer and its share price is yield-only by construction:
///      the underlying Liquidity exchange price only accrues upward and rewards only add to it.
///      Deposits and withdrawals scale `totalAssets` and `totalSupply` together, so the ratio is
///      flat on principal flows and rises with yield. Any decrease therefore signals a loss,
///      mispriced mint/redeem, or accounting bug — exactly what an ERC-4626 holder needs protected.
///
///      Checked at transaction end by sampling `convertToAssets(1e12)`, which is Fluid's underlying
///      token exchange price scale. This avoids `totalAssets()` floor-rounding differences caused by
///      supply changes while still checking the holder-facing share price. Empty-vault snapshots are
///      skipped because share price is undefined with no shares.
contract FluidFTokenSharePriceAssertion is Assertion {
    /// @notice Strictly non-decreasing: share price may rise (yield) but never fall.
    uint256 internal constant PRICE_SAMPLE_SHARES = 1e12;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the transaction-end share-price check.
    function triggers() external view override {
        registerTxEndTrigger(this.assertSharePriceNonDecreasing.selector);
    }

    /// @notice fToken share price sampled with a fixed share amount does not decrease.
    /// @dev Reads the fToken's `totalSupply()` and `convertToAssets(1e12)` at PreTx and PostTx. A
    ///      failure means the transaction reduced the value backing a fixed share quantity — a
    ///      yield-only vault must never do this. Snapshots with zero supply are skipped (share price
    ///      undefined).
    function assertSharePriceNonDecreasing() external view {
        address fToken = ph.getAssertionAdopter();

        uint256 preSupply = _readUintAt(fToken, abi.encodeCall(IFTokenLike.totalSupply, ()), _preTx());
        uint256 postSupply = _readUintAt(fToken, abi.encodeCall(IFTokenLike.totalSupply, ()), _postTx());
        if (preSupply == 0 || postSupply == 0) return;

        uint256 preAssets =
            _readUintAt(fToken, abi.encodeCall(IFTokenLike.convertToAssets, (PRICE_SAMPLE_SHARES)), _preTx());
        uint256 postAssets =
            _readUintAt(fToken, abi.encodeCall(IFTokenLike.convertToAssets, (PRICE_SAMPLE_SHARES)), _postTx());

        require(postAssets >= preAssets, "Fluid: fToken share price decreased");
    }
}
