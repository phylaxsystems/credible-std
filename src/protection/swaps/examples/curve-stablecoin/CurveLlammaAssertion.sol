// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";
import {CurveLlammaProtocolHelpers} from "./CurveLlammaProtocol.sol";

/// @title CurveLlammaAssertion
/// @notice Example LLAMMA checks for band custody, band layout, swap price bounds,
///         and a hard cumulative inflow circuit breaker on both token legs.
contract CurveLlammaAssertion is CurveLlammaProtocolHelpers {
    uint256 public constant INFLOW_THRESHOLD_BPS = 1_000;
    uint256 public constant INFLOW_WINDOW_DURATION = 6 hours;

    constructor(
        address amm_,
        uint256 borrowedPrecision_,
        uint256 collateralPrecision_,
        uint256 maxBandsToScan_,
        uint256 dustTolerance_,
        uint256 priceTolerance_
    )
        CurveLlammaProtocolHelpers(
            amm_, borrowedPrecision_, collateralPrecision_, maxBandsToScan_, dustTolerance_, priceTolerance_
        )
    {}

    /// @notice Registers checks over band sums vs ERC20 custody, one-sided inactive bands, swap prices,
    ///         and 10% token inflow caps over a rolling 6 hour window for both AMM legs.
    function triggers() external view override {
        watchCumulativeInflow(
            borrowedToken, INFLOW_THRESHOLD_BPS, INFLOW_WINDOW_DURATION, this.assertCumulativeInflow.selector
        );
        watchCumulativeInflow(
            collateralToken, INFLOW_THRESHOLD_BPS, INFLOW_WINDOW_DURATION, this.assertCumulativeInflow.selector
        );
        registerTxEndTrigger(this.assertAMMCustodyCoversBands.selector);
        registerTxEndTrigger(this.assertBandShape.selector);
        _registerLlammaSwapTriggers(this.assertPostSwapPriceInsideActiveBand.selector);
    }

    /// @notice Hard circuit breaker that blocks transactions while either monitored inflow stays above threshold.
    function assertCumulativeInflow() external pure {
        revert("CurveLLAMMA: cumulative inflow breaker tripped");
    }

    /// @notice Compares AMM ERC20 balances with summed `bands_x` and `bands_y` across scanned bands.
    function assertAMMCustodyCoversBands() external {
        PhEvm.ForkId memory fork = _postTx();
        int256 minBand = _ammMinBandAt(fork);
        int256 maxBand = _ammMaxBandAt(fork);
        uint256 span = _bandSpan(minBand, maxBand);

        uint256 sumX;
        uint256 sumY;
        for (uint256 offset; offset < span; ++offset) {
            int256 band = _bandAt(minBand, offset);
            sumX += _ammBandXAt(band, fork);
            sumY += _ammBandYAt(band, fork);
        }

        uint256 borrowedBalance = _readBalanceAt(borrowedToken, amm, fork);
        uint256 collateralBalance = _readBalanceAt(collateralToken, amm, fork);

        require(
            borrowedBalance * borrowedPrecision + dustTolerance >= sumX, "CurveLLAMMA: borrowed custody below bands_x"
        );
        require(
            collateralBalance * collateralPrecision + dustTolerance >= sumY,
            "CurveLLAMMA: collateral custody below bands_y"
        );
    }

    /// @notice Checks `bands_y == 0` below `active_band` and `bands_x == 0` above it.
    function assertBandShape() external {
        PhEvm.ForkId memory fork = _postTx();
        int256 active = _ammActiveBandAt(fork);
        int256 minBand = _ammMinBandAt(fork);
        int256 maxBand = _ammMaxBandAt(fork);
        uint256 span = _bandSpan(minBand, maxBand);

        for (uint256 offset; offset < span; ++offset) {
            int256 band = _bandAt(minBand, offset);
            uint256 x = _ammBandXAt(band, fork);
            uint256 y = _ammBandYAt(band, fork);

            if (band < active) {
                require(y == 0, "CurveLLAMMA: collateral below active band");
            }

            if (band > active) {
                require(x == 0, "CurveLLAMMA: borrowed token above active band");
            }
        }
    }

    /// @notice Checks `get_p()` stays between `p_current_down` and `p_current_up` for the active band.
    function assertPostSwapPriceInsideActiveBand() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory fork = _postCall(ctx.callEnd);

        int256 active = _ammActiveBandAt(fork);
        uint256 price = _ammPriceAt(fork);
        uint256 priceDown = _ammBandPriceDownAt(active, fork);
        uint256 priceUp = _ammBandPriceUpAt(active, fork);

        require(price + priceTolerance >= priceDown, "CurveLLAMMA: price below active band");
        require(price <= priceUp + priceTolerance, "CurveLLAMMA: price above active band");
    }
}
