// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {FluidLiquidityBase} from "./FluidLiquidityHelpers.sol";

/// @title FluidLiquiditySolvencyAssertion
/// @author Phylax Systems
/// @notice Persisted exchange-price monotonicity for the Fluid Liquidity Layer singleton.
/// @dev Install on the Liquidity Layer proxy (the assertion adopter). Reads the singleton's packed
///      per-token accounting directly from storage via `FluidLiquidityBase`. Protects two
///      one property that can be evaluated from persisted state without replaying Fluid's current
///      accrual math: supply/borrow exchange prices only accrue interest and never decrease.
///      A previous custody check valued newly-written raw totals with stale persisted prices even
///      when a valid `operate` had calculated newer prices but did not cross the persistence
///      threshold. That mixed-time equation rejected solvent operations and was removed.
contract FluidLiquiditySolvencyAssertion is FluidLiquidityBase {
    /// @notice Tokens whose Liquidity Layer accounting this assertion protects.
    address[] internal tokens;

    /// @param tokens_ Monitored token addresses (e.g. USDC, USDT, WETH, wstETH, GHO).
    constructor(address[] memory tokens_) {
        require(tokens_.length != 0, "Fluid: empty token list");
        for (uint256 i; i < tokens_.length; ++i) {
            require(tokens_[i] != address(0), "Fluid: zero token");
            for (uint256 j; j < i; ++j) {
                require(tokens_[j] != tokens_[i], "Fluid: duplicate token");
            }
        }
        tokens = tokens_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers persisted exchange-price monotonicity at transaction end.
    function triggers() external view override {
        registerTxEndTrigger(this.assertExchangePricesMonotonic.selector);
    }

    /// @notice Supply and borrow exchange prices never decrease across a transaction.
    /// @dev Fluid exchange prices only ever accrue interest (`+=`), so a decrease from PreTx to
    ///      PostTx signals corrupted accounting or a malicious write to the packed config slot —
    ///      which would let withdrawals exceed entitlement or under-charge borrowers. Equality is
    ///      the normal case (prices are already accrued to the current block at both snapshots).
    function assertExchangePricesMonotonic() external view {
        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();

        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            address token = tokens[i];

            (uint256 preSupply, uint256 preBorrow) = _liquidityExchangePrices(token, pre);
            (uint256 postSupply, uint256 postBorrow) = _liquidityExchangePrices(token, post);

            require(postSupply >= preSupply, "Fluid: supply exchange price decreased");
            require(postBorrow >= preBorrow, "Fluid: borrow exchange price decreased");
        }
    }
}
