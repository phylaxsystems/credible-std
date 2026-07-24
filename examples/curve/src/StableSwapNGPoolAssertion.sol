// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {StableSwapNGProtocolHelpers} from "./StableSwapNGProtocol.sol";

/// @title StableSwapNGPoolAssertion
/// @notice Example StableSwap NG checks for custody, fees, oracles, metapool accounting, and virtual price.
contract StableSwapNGPoolAssertion is StableSwapNGProtocolHelpers {
    constructor(address pool_, uint256 maxCoinsToScan_, uint256 dustTolerance_, uint256 virtualPriceTolerance_)
        StableSwapNGProtocolHelpers(pool_, maxCoinsToScan_, dustTolerance_, virtualPriceTolerance_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers checks over pool custody, admin fees, fee caps, oracle bounds, metapool rates, and virtual price.
    function triggers() external view override {
        registerTxEndTrigger(this.assertPoolCustodyCoversAccounting.selector);
        registerTxEndTrigger(this.assertAdminBalancesCovered.selector);
        registerTxEndTrigger(this.assertFeeBounds.selector);
        registerTxEndTrigger(this.assertOracleBounds.selector);
        registerTxEndTrigger(this.assertMetapoolBaseLpAccounting.selector);
        _registerStableSwapNGVirtualPriceTriggers(this.assertVirtualPriceNonDecreasing.selector);
    }

    /// @notice Compares each coin balance with `balances(i) + admin_balances(i)`.
    function assertPoolCustodyCoversAccounting() external {
        require(ph.getAssertionAdopter() == pool, "StableSwapNG: configured pool is not adopter");
        PhEvm.ForkId memory fork = _postTx();
        uint256 coinCount = _stableSwapCoinCountAt(fork);

        for (uint256 i; i < coinCount; ++i) {
            StableSwapNGCoinAccounting memory accounting = _stableSwapCoinAccountingAt(i, fork);
            require(accounting.actual + dustTolerance >= accounting.accounted, "StableSwapNG: token custody shortfall");
        }
    }

    /// @notice Checks each `admin_balances(i)` stays within actual coin custody.
    function assertAdminBalancesCovered() external {
        require(ph.getAssertionAdopter() == pool, "StableSwapNG: configured pool is not adopter");
        PhEvm.ForkId memory fork = _postTx();
        uint256 coinCount = _stableSwapCoinCountAt(fork);

        for (uint256 i; i < coinCount; ++i) {
            StableSwapNGCoinAccounting memory accounting = _stableSwapCoinAccountingAt(i, fork);
            require(
                accounting.adminBalance <= accounting.actual + dustTolerance,
                "StableSwapNG: admin balance exceeds actual"
            );
        }
    }

    /// @notice Checks the fee configuration used by the pool stays within NG caps.
    /// @dev The public `dynamic_fee` view is delegated to an upgradeable factory implementation
    ///      and is not the swap's internal fee calculation, so it is deliberately not trusted.
    function assertFeeBounds() external {
        require(ph.getAssertionAdopter() == pool, "StableSwapNG: configured pool is not adopter");
        PhEvm.ForkId memory fork = _postTx();
        StableSwapNGFeeState memory feeState = _stableSwapFeeStateAt(fork);

        require(_stableSwapFeeCapHolds(feeState.fee, feeState.offpegFeeMultiplier), "StableSwapNG: fee cap broken");
    }

    /// @notice Checks `last_price`, `ema_price`, and `D_oracle` stay initialized and capped.
    function assertOracleBounds() external {
        require(ph.getAssertionAdopter() == pool, "StableSwapNG: configured pool is not adopter");
        PhEvm.ForkId memory fork = _postTx();
        uint256 coinCount = _stableSwapCoinCountAt(fork);
        uint256 totalSupply = _stableSwapTotalSupplyAt(fork);

        for (uint256 i; i + 1 < coinCount; ++i) {
            StableSwapNGOracleState memory oracleState = _stableSwapOracleStateAt(i, fork);

            require(oracleState.lastPrice <= ORACLE_PRICE_CAP, "StableSwapNG: last price cap broken");
            if (totalSupply > 0) {
                require(oracleState.lastPrice > 0, "StableSwapNG: zero last price");
                require(oracleState.emaPrice > 0, "StableSwapNG: zero EMA price");
                require(oracleState.emaPrice <= ORACLE_PRICE_CAP, "StableSwapNG: EMA price cap broken");
            }
        }

        if (totalSupply > 0) {
            uint256 dOracle = _stableSwapDOracleAt(fork);
            require(dOracle > 0, "StableSwapNG: zero D oracle");
        }
    }

    /// @notice Checks base-LP custody covers slot-1 accounting and the stored base rate tracks base-pool virtual price.
    function assertMetapoolBaseLpAccounting() external {
        require(ph.getAssertionAdopter() == pool, "StableSwapNG: configured pool is not adopter");
        PhEvm.ForkId memory fork = _postTx();
        (bool hasBasePool, address basePool) = _stableSwapBasePoolAt(fork);
        if (!hasBasePool) {
            return;
        }

        StableSwapNGCoinAccounting memory baseLpAccounting = _stableSwapCoinAccountingAt(1, fork);
        require(
            baseLpAccounting.actual + dustTolerance >= baseLpAccounting.accounted,
            "StableSwapNG: base LP custody shortfall"
        );

        uint256[] memory rates = _stableSwapStoredRatesAt(fork);
        require(rates.length > 1, "StableSwapNG: missing base LP rate");

        uint256 baseVirtualPrice = _stableSwapBasePoolVirtualPriceAt(basePool, fork);
        require(rates[1] == baseVirtualPrice, "StableSwapNG: base LP rate mismatch");
    }

    /// @notice Checks guarded user actions do not lower `get_virtual_price()` from pre-call to post-call.
    function assertVirtualPriceNonDecreasing() external {
        require(ph.getAssertionAdopter() == pool, "StableSwapNG: configured pool is not adopter");
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);

        if (!_stableSwapCanCheckVirtualPrice(beforeFork, afterFork)) {
            return;
        }

        uint256 preVirtualPrice = _stableSwapVirtualPriceAt(beforeFork);
        uint256 postVirtualPrice = _stableSwapVirtualPriceAt(afterFork);

        require(postVirtualPrice + virtualPriceTolerance >= preVirtualPrice, "StableSwapNG: virtual price decreased");
    }
}
