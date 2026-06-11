// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {FluidLiquidityBase} from "./FluidLiquidityHelpers.sol";
import {IFluidLiquidityLike} from "./FluidInterfaces.sol";

/// @title FluidLiquidityFlowBreakerAssertion
/// @author Phylax Systems
/// @notice Rolling-window outflow circuit breaker for the Fluid Liquidity Layer singleton.
/// @dev Fluid's on-chain per-protocol withdraw/borrow limits auto-expand over time and are kept
///      generous for capital efficiency. This assertion lets those on-chain limits stay loose while
///      bounding the *aggregate* token bleed in a rolling window, so a single exploit cannot drain a
///      market by chaining many individually-valid `operate` calls. The policy is tiered per token:
///      - Warning tier (10% net outflow / 24h): block new borrows; suppliers may still withdraw and
///        borrowers may still repay, so honest exit and de-risking stay open.
///      - Critical tier (20% net outflow / 24h): hard-pause the singleton.
///      Outflow accounting (TVL snapshot, window bucketing) is handled by the built-in breaker.
contract FluidLiquidityFlowBreakerAssertion is FluidLiquidityBase {
    uint256 public constant WARN_OUTFLOW_BPS = 1_000; // 10%
    uint256 public constant CRITICAL_OUTFLOW_BPS = 2_000; // 20%
    uint256 public constant OUTFLOW_WINDOW = 24 hours;

    /// @notice `operate`'s `token_` is calldata arg 0 and `borrowAmount_` is calldata arg 2.
    uint256 internal constant OPERATE_TOKEN_ARG = 0;
    uint256 internal constant OPERATE_BORROW_ARG = 2;

    /// @notice Tokens watched by the breaker.
    address[] internal tokens;

    /// @param tokens_ Monitored token addresses (the Liquidity Layer markets to rate-limit).
    constructor(address[] memory tokens_) {
        tokens = tokens_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the warning and critical outflow watchers for each monitored token.
    function triggers() external view override {
        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            address token = tokens[i];
            watchCumulativeOutflow(
                token, WARN_OUTFLOW_BPS, OUTFLOW_WINDOW, this.assertNoBorrowAfterLargeOutflow.selector
            );
            watchCumulativeOutflow(
                token, CRITICAL_OUTFLOW_BPS, OUTFLOW_WINDOW, this.assertCriticalOutflowPause.selector
            );
        }
    }

    /// @notice After 10% net outflow of a token in 24h, no new borrow of that token may execute.
    /// @dev Triggered by the warning-tier breaker. Scans every `operate` call on the singleton and
    ///      fails if one borrows (`borrowAmount_ > 0`) the token that breached the window. Repays
    ///      (`borrowAmount_ < 0`), supplies and withdrawals are allowed so the market can de-risk and
    ///      suppliers can still exit. A failure means a borrow was attempted while the market was
    ///      already bleeding past the warning threshold.
    function assertNoBorrowAfterLargeOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(_isWatched(ctx.token), "Fluid: unwatched outflow token");

        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(_liquidity(), IFluidLiquidityLike.operate.selector);
        for (uint256 i; i < calls.length; ++i) {
            if (_operateBorrowsToken(ph.callinputAt(calls[i].id), ctx.token)) {
                revert("Fluid: borrow disabled after large outflow");
            }
        }
    }

    /// @notice Pure policy decision: does this `operate` calldata borrow `token`?
    /// @dev A borrow is `borrowAmount_ > 0` for the breached token; repays (`< 0`), supplies, and
    ///      operations on other tokens return false. Extracted so the policy is unit-testable without
    ///      the live outflow trigger context (which local `pcl test` does not simulate).
    function _operateBorrowsToken(bytes memory input, address token) internal pure returns (bool) {
        return _addressArg(input, OPERATE_TOKEN_ARG) == token && _int256Arg(input, OPERATE_BORROW_ARG) > 0;
    }

    /// @notice After 20% net outflow of a token in 24h, hard-pause the Liquidity Layer.
    /// @dev Triggered by the critical-tier breaker. Reverts the whole transaction; recovery requires
    ///      the window to slide forward (outflow to subside) or governance to intervene.
    function assertCriticalOutflowPause() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(_isWatched(ctx.token), "Fluid: unwatched outflow token");

        revert("Fluid: critical liquidity outflow pause");
    }

    function _isWatched(address token) internal view returns (bool) {
        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            if (tokens[i] == token) return true;
        }
        return false;
    }
}
