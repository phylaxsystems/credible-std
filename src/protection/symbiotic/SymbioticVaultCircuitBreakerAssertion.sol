// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {SymbioticHelpers} from "./SymbioticHelpers.sol";
import {ISymbioticVaultLike} from "./SymbioticInterfaces.sol";

/// @title SymbioticVaultCircuitBreakerAssertion
/// @author Phylax Systems
/// @notice Two-tier cumulative outflow circuit breaker for a Symbiotic vault's collateral.
/// @dev This uses `watchCumulativeOutflow`, so once the soft threshold is breached the assertion
///      keeps firing on every later transaction that touches the vault until enough collateral
///      flows back in to bring the rolling window back under the limit.
///
///      The soft tier is "liquidation-aware":
///      - if the current transaction does not create new net collateral outflow, allow it so
///        deposits or other healing flows can continue;
///      - if the current transaction does create new net outflow, allow it only when the tx
///        includes one of the configured liquidation calls;
///      - otherwise revert.
///
///      The hard tier is a full stop: once the larger rolling-window threshold is breached, all
///      later touching transactions revert until the outflow state recovers below the threshold.
abstract contract SymbioticVaultCircuitBreakerAssertion is SymbioticHelpers {
    struct LiquidationRoute {
        address target;
        bytes4 selector;
    }

    /// @notice Hourly soft tier: 10% of the vault collateral TVL snapshot.
    uint256 public constant HOURLY_THRESHOLD_BPS = 1_000;
    uint256 public constant HOURLY_WINDOW_DURATION = 1 hours;

    /// @notice Daily hard tier: 30% of the vault collateral TVL snapshot.
    uint256 public constant DAILY_THRESHOLD_BPS = 3_000;
    uint256 public constant DAILY_WINDOW_DURATION = 24 hours;

    address internal immutable vault;
    address internal immutable asset;

    /// @notice Allowlisted liquidation entry points that may legitimately increase outflow.
    LiquidationRoute[] public liquidationRoutes;

    constructor(address vault_, LiquidationRoute[] memory liquidationRoutes_) {
        require(vault_ != address(0), "SymbioticCircuitBreaker: vault is zero");
        require(liquidationRoutes_.length != 0, "SymbioticCircuitBreaker: missing liquidation routes");

        vault = vault_;
        asset = ISymbioticVaultLike(vault_).collateral();

        for (uint256 i; i < liquidationRoutes_.length; ++i) {
            require(liquidationRoutes_[i].target != address(0), "SymbioticCircuitBreaker: liquidation target is zero");
            require(
                liquidationRoutes_[i].selector != bytes4(0),
                "SymbioticCircuitBreaker: liquidation selector is zero"
            );
            liquidationRoutes.push(liquidationRoutes_[i]);
        }
    }

    /// @notice Register both cumulative outflow tiers on the vault collateral.
    function _registerCircuitBreakerTriggers() internal view {
        watchCumulativeOutflow(
            asset,
            HOURLY_THRESHOLD_BPS,
            HOURLY_WINDOW_DURATION,
            this.assertHourlyLiquidationAwareCircuitBreaker.selector
        );
        watchCumulativeOutflow(
            asset, DAILY_THRESHOLD_BPS, DAILY_WINDOW_DURATION, this.assertDailyHardStopCircuitBreaker.selector
        );
    }

    /// @notice Soft circuit breaker for the 10% / 1h tier.
    /// @dev The important subtlety from `watchCumulativeOutflow` is that once breached, this
    ///      function runs on every later tx that touches the vault. Because of that, we should
    ///      not blindly revert: deposits and other healing flows must still be able to proceed.
    function assertHourlyLiquidationAwareCircuitBreaker() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();

        require(ctx.token == asset, "SymbioticCircuitBreaker: unexpected outflow token");

        // When the vault is already in a stressed outflow state, ordinary user exits should stop
        // even if the current tx is only queueing a future withdrawal.
        require(!_hasBlockedUserExitCall(), "SymbioticCircuitBreaker: user exits blocked during hourly breach");

        // If this tx does not worsen net collateral outflow, let it through so the vault can heal.
        if (_currentTxNetOutflow() == 0) {
            return;
        }

        // Net new outflow is only acceptable here when it comes from a known liquidation path.
        require(
            _hasApprovedLiquidationCall(),
            "SymbioticCircuitBreaker: hourly outflow breach without approved liquidation"
        );
    }

    /// @notice Hard circuit breaker for the 30% / 24h tier.
    /// @dev This is an unconditional stop by design.
    function assertDailyHardStopCircuitBreaker() external pure {
        revert("SymbioticCircuitBreaker: daily hard outflow breaker tripped");
    }

    /// @notice Returns true when the transaction contains an allowlisted liquidation call.
    function _hasApprovedLiquidationCall() internal view returns (bool) {
        for (uint256 i; i < liquidationRoutes.length; ++i) {
            if (_matchingCalls(liquidationRoutes[i].target, liquidationRoutes[i].selector, 1).length != 0) {
                return true;
            }
        }
        return false;
    }

    /// @notice Returns true when the transaction contains a normal vault exit path.
    /// @dev These are blocked during the soft breach window so the breaker behaves like
    ///      a liquidation-and-healing-only mode rather than a blanket pass for all activity.
    function _hasBlockedUserExitCall() internal view returns (bool) {
        return _matchingCalls(vault, ISymbioticVaultLike.withdraw.selector, 1).length != 0
            || _matchingCalls(vault, ISymbioticVaultLike.redeem.selector, 1).length != 0
            || _matchingCalls(vault, ISymbioticVaultLike.claim.selector, 1).length != 0
            || _matchingCalls(vault, ISymbioticVaultLike.claimBatch.selector, 1).length != 0;
    }

    /// @notice Computes the current transaction's net outflow from the vault for the monitored asset.
    /// @dev This is tx-local, not the rolling-window value from `ph.outflowContext()`.
    function _currentTxNetOutflow() internal view returns (uint256 netOutflow) {
        PhEvm.Erc20TransferData[] memory deltas = _reducedErc20BalanceDeltasAt(asset, _postTx());
        uint256 totalOutflow;
        uint256 totalInflow;

        // Look only at the vault's point of view: transfers out increase pressure, transfers in heal it.
        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == vault) {
                totalOutflow += deltas[i].value;
            }
            if (deltas[i].to == vault) {
                totalInflow += deltas[i].value;
            }
        }

        return _consumedBetween(totalOutflow, totalInflow);
    }
}

/// @title SymbioticVaultCircuitBreakerProtection
/// @notice Ready-to-use bundle for the Symbiotic vault liquidation-aware circuit breaker.
contract SymbioticVaultCircuitBreakerProtection is SymbioticVaultCircuitBreakerAssertion {
    constructor(address vault_, LiquidationRoute[] memory liquidationRoutes_)
        SymbioticVaultCircuitBreakerAssertion(vault_, liquidationRoutes_)
    {}

    function triggers() external view override {
        _registerCircuitBreakerTriggers();
    }
}
