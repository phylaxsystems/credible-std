// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {FluidLiquidityBase} from "./FluidLiquidityHelpers.sol";

/// @title FluidLiquiditySolvencyAssertion
/// @author Phylax Systems
/// @notice Core accounting invariants for the Fluid Liquidity Layer singleton.
/// @dev Install on the Liquidity Layer proxy (the assertion adopter). Reads the singleton's packed
///      per-token accounting directly from storage via `FluidLiquidityBase`. Protects two
///      properties that the protocol's per-operation `require`s do not express against external
///      state at transaction end:
///      - Custody: the tokens actually held cover what suppliers are owed net of outstanding debt.
///      - Monotonicity: supply/borrow exchange prices only accrue interest, never decrease.
///      Native-token markets (0xEeee...EEeE) are skipped by the custody check because their balance
///      is ETH, not an ERC20 balanceOf; the monotonicity check still applies to them. Mainnet
///      weETH/weETHs custody includes Fluid's recognized Zircuit balances.
contract FluidLiquiditySolvencyAssertion is FluidLiquidityBase {
    /// @notice Allowed solvency shortfall, as a fraction of total supply (1 / 1e6 = 0.0001%).
    /// @dev Absorbs BigMath storage truncation and same-tx revenue-accrual rounding only; far below
    ///      any meaningful drain.
    uint256 internal constant SOLVENCY_TOLERANCE_DENOM = 1e6;

    /// @notice Tokens whose Liquidity Layer accounting this assertion protects.
    address[] internal tokens;

    /// @param tokens_ Monitored token addresses (e.g. USDC, USDT, WETH, wstETH, GHO).
    constructor(address[] memory tokens_) {
        tokens = tokens_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers both Liquidity Layer envelope checks at transaction end.
    function triggers() external view override {
        registerTxEndTrigger(this.assertCustodyCoversNetSupply.selector);
        registerTxEndTrigger(this.assertExchangePricesMonotonic.selector);
    }

    /// @notice The Liquidity Layer holds enough of each token to cover supplier claims net of debt.
    /// @dev Property: `balanceOf(Liquidity, token) + totalBorrow >= totalSupply` for every monitored
    ///      token, i.e. accrued protocol revenue stays non-negative. A failure means a transaction
    ///      left the singleton unable to back its suppliers from custody plus recoverable debt —
    ///      the protocol-wide insolvency condition. Checked at transaction end so it holds after all
    ///      borrows, withdrawals, repayments and revenue movements in the transaction.
    function assertCustodyCoversNetSupply() external view {
        PhEvm.ForkId memory post = _postTx();
        address liquidity = _liquidity();

        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            address token = tokens[i];
            if (token == NATIVE_TOKEN) continue;

            (uint256 totalSupply, uint256 totalBorrow) = _liquidityTotals(token, post);
            uint256 held = _liquidityCustodyBalance(token, liquidity, post);

            uint256 tolerance = totalSupply / SOLVENCY_TOLERANCE_DENOM;
            require(held + totalBorrow + tolerance >= totalSupply, "Fluid: liquidity custody below net supply");
        }
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
