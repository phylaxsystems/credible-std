// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";
import {TriCryptoNGProtocolHelpers} from "./TriCryptoNGProtocol.sol";

/// @title TriCryptoNGPoolAssertion
/// @notice Example TriCrypto NG checks for custody, fees, oracle initialization, profit counters, and virtual price.
contract TriCryptoNGPoolAssertion is TriCryptoNGProtocolHelpers {
    constructor(
        address pool_,
        address wrappedNativeToken_,
        uint256 dustTolerance_,
        uint256 virtualPriceToleranceBps_,
        uint256 profitTolerance_
    )
        TriCryptoNGProtocolHelpers(
            pool_, wrappedNativeToken_, dustTolerance_, virtualPriceToleranceBps_, profitTolerance_
        )
    {}

    /// @notice Registers checks over ERC20 custody, fee params, oracle state, profit counters, and virtual price.
    function triggers() external view override {
        registerTxEndTrigger(this.assertPoolCustodyCoversBalances.selector);
        registerTxEndTrigger(this.assertFeeBounds.selector);
        registerTxEndTrigger(this.assertOracleValuesInitialized.selector);
        registerTxEndTrigger(this.assertProfitAndVirtualPriceBounds.selector);
        _registerTriCryptoVirtualPriceTriggers(this.assertVirtualPriceNonDecreasing.selector);
    }

    /// @notice Compares each non-native coin balance with the pool's internal `balances(i)`.
    function assertPoolCustodyCoversBalances() external {
        PhEvm.ForkId memory fork = _postTx();

        for (uint256 i; i < N_COINS; ++i) {
            TriCryptoNGCoinAccounting memory accounting = _triCryptoCoinAccountingAt(i, fork);
            if (!accounting.shouldCheckCustody) {
                continue;
            }

            require(accounting.actual + dustTolerance >= accounting.accounted, "TriCryptoNG: token custody shortfall");
        }
    }

    /// @notice Checks live fee parameters stay within the pool's configured TriCrypto bounds.
    function assertFeeBounds() external {
        PhEvm.ForkId memory fork = _postTx();
        TriCryptoNGFeeState memory feeState = _triCryptoFeeStateAt(fork);

        require(feeState.midFee >= MIN_FEE, "TriCryptoNG: mid fee too low");
        require(feeState.midFee <= feeState.outFee, "TriCryptoNG: mid fee above out fee");
        require(feeState.outFee <= MAX_FEE, "TriCryptoNG: out fee too high");
        require(feeState.fee >= feeState.midFee, "TriCryptoNG: fee below mid fee");
        require(feeState.fee <= feeState.outFee, "TriCryptoNG: fee above out fee");
        require(feeState.feeGamma > 0 && feeState.feeGamma <= WAD, "TriCryptoNG: fee gamma out of bounds");
    }

    /// @notice Checks `price_scale`, `price_oracle`, and `last_prices` stay initialized.
    function assertOracleValuesInitialized() external {
        PhEvm.ForkId memory fork = _postTx();
        uint256 totalSupply = _triCryptoTotalSupplyAt(fork);

        for (uint256 k; k < N_PRICE_PAIRS; ++k) {
            TriCryptoNGOracleState memory oracleState = _triCryptoOracleStateAt(k, fork);

            require(oracleState.priceScale > 0, "TriCryptoNG: zero price scale");
            if (totalSupply > 0) {
                require(oracleState.priceOracle > 0, "TriCryptoNG: zero price oracle");
                require(oracleState.lastPrice > 0, "TriCryptoNG: zero last price");
            }
        }
    }

    /// @notice Checks profit counters stay ordered and cached and live virtual prices stay initialized.
    function assertProfitAndVirtualPriceBounds() external {
        PhEvm.ForkId memory fork = _postTx();
        TriCryptoNGProfitState memory profitState = _triCryptoProfitStateAt(fork);
        if (profitState.totalSupply == 0) {
            return;
        }

        require(
            _gteWithAbsoluteTolerance(profitState.cachedVirtualPrice, WAD, profitTolerance),
            "TriCryptoNG: cached VP below 1"
        );
        require(
            _gteWithAbsoluteTolerance(profitState.liveVirtualPrice, WAD, profitTolerance),
            "TriCryptoNG: live VP below 1"
        );
        require(
            _gteWithAbsoluteTolerance(profitState.xcpProfit, WAD, profitTolerance), "TriCryptoNG: xcp profit below 1"
        );
        require(
            _gteWithAbsoluteTolerance(profitState.xcpProfitA, WAD, profitTolerance), "TriCryptoNG: xcp profit_a below 1"
        );
        require(
            _withinBps(profitState.cachedVirtualPrice, profitState.liveVirtualPrice, virtualPriceToleranceBps),
            "TriCryptoNG: cached/live VP mismatch"
        );

        if (profitState.cachedVirtualPrice >= WAD && profitState.xcpProfit >= WAD) {
            uint256 virtualProfit = profitState.cachedVirtualPrice - WAD;
            uint256 xcpExcess = profitState.xcpProfit - WAD;
            require(virtualProfit * 2 + profitTolerance >= xcpExcess, "TriCryptoNG: virtual profit below xcp");
        }
    }

    /// @notice Checks guarded user actions do not lower live virtual price from pre-call to post-call.
    function assertVirtualPriceNonDecreasing() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);

        if (!_triCryptoCanCheckVirtualPrice(beforeFork, afterFork)) {
            return;
        }

        uint256 preVirtualPrice = _triCryptoLiveVirtualPriceAt(beforeFork);
        uint256 postVirtualPrice = _triCryptoLiveVirtualPriceAt(afterFork);

        require(postVirtualPrice + profitTolerance >= preVirtualPrice, "TriCryptoNG: virtual price decreased");
    }
}
