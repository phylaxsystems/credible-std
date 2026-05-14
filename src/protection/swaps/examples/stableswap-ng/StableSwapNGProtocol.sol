// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";

interface IStableSwapNGPool {
    function N_COINS() external view returns (uint256);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function admin_balances(uint256 i) external view returns (uint256);
    function fee() external view returns (uint256);
    function offpeg_fee_multiplier() external view returns (uint256);
    function dynamic_fee(int128 i, int128 j) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function stored_rates() external view returns (uint256[] memory);
    function A_precise() external view returns (uint256);
    function last_price(uint256 i) external view returns (uint256);
    function ema_price(uint256 i) external view returns (uint256);
    function D_oracle() external view returns (uint256);
}

interface IStableSwapNGMetaPool {
    function BASE_POOL() external view returns (address);
}

library StableSwapNGSelectors {
    bytes4 internal constant EXCHANGE = bytes4(keccak256("exchange(int128,int128,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_RECEIVER = bytes4(keccak256("exchange(int128,int128,uint256,uint256,address)"));
    bytes4 internal constant EXCHANGE_RECEIVED = bytes4(keccak256("exchange_received(int128,int128,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_RECEIVED_RECEIVER =
        bytes4(keccak256("exchange_received(int128,int128,uint256,uint256,address)"));
    bytes4 internal constant EXCHANGE_UNDERLYING =
        bytes4(keccak256("exchange_underlying(int128,int128,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_UNDERLYING_RECEIVER =
        bytes4(keccak256("exchange_underlying(int128,int128,uint256,uint256,address)"));

    bytes4 internal constant ADD_LIQUIDITY_DYNAMIC = bytes4(keccak256("add_liquidity(uint256[],uint256)"));
    bytes4 internal constant ADD_LIQUIDITY_DYNAMIC_RECEIVER =
        bytes4(keccak256("add_liquidity(uint256[],uint256,address)"));
    bytes4 internal constant ADD_LIQUIDITY_META = bytes4(keccak256("add_liquidity(uint256[2],uint256)"));
    bytes4 internal constant ADD_LIQUIDITY_META_RECEIVER =
        bytes4(keccak256("add_liquidity(uint256[2],uint256,address)"));

    bytes4 internal constant REMOVE_LIQUIDITY_DYNAMIC = bytes4(keccak256("remove_liquidity(uint256,uint256[])"));
    bytes4 internal constant REMOVE_LIQUIDITY_DYNAMIC_RECEIVER =
        bytes4(keccak256("remove_liquidity(uint256,uint256[],address)"));
    bytes4 internal constant REMOVE_LIQUIDITY_DYNAMIC_RECEIVER_CLAIM =
        bytes4(keccak256("remove_liquidity(uint256,uint256[],address,bool)"));
    bytes4 internal constant REMOVE_LIQUIDITY_META = bytes4(keccak256("remove_liquidity(uint256,uint256[2])"));
    bytes4 internal constant REMOVE_LIQUIDITY_META_RECEIVER =
        bytes4(keccak256("remove_liquidity(uint256,uint256[2],address)"));
    bytes4 internal constant REMOVE_LIQUIDITY_META_RECEIVER_CLAIM =
        bytes4(keccak256("remove_liquidity(uint256,uint256[2],address,bool)"));

    bytes4 internal constant REMOVE_ONE = bytes4(keccak256("remove_liquidity_one_coin(uint256,int128,uint256)"));
    bytes4 internal constant REMOVE_ONE_RECEIVER =
        bytes4(keccak256("remove_liquidity_one_coin(uint256,int128,uint256,address)"));

    bytes4 internal constant REMOVE_IMBALANCE_DYNAMIC =
        bytes4(keccak256("remove_liquidity_imbalance(uint256[],uint256)"));
    bytes4 internal constant REMOVE_IMBALANCE_DYNAMIC_RECEIVER =
        bytes4(keccak256("remove_liquidity_imbalance(uint256[],uint256,address)"));
    bytes4 internal constant REMOVE_IMBALANCE_META =
        bytes4(keccak256("remove_liquidity_imbalance(uint256[2],uint256)"));
    bytes4 internal constant REMOVE_IMBALANCE_META_RECEIVER =
        bytes4(keccak256("remove_liquidity_imbalance(uint256[2],uint256,address)"));
}

abstract contract StableSwapNGProtocolHelpers is Assertion {
    uint256 internal constant MAX_FEE = 5e9;
    uint256 internal constant FEE_DENOMINATOR = 1e10;
    uint256 internal constant ORACLE_PRICE_CAP = 2e18;

    address internal immutable pool;
    uint256 internal immutable maxCoinsToScan;
    uint256 internal immutable dustTolerance;
    uint256 internal immutable virtualPriceTolerance;

    struct StableSwapNGCoinAccounting {
        address coin;
        uint256 lpBalance;
        uint256 adminBalance;
        uint256 accounted;
        uint256 actual;
    }

    struct StableSwapNGFeeState {
        uint256 fee;
        uint256 offpegFeeMultiplier;
    }

    struct StableSwapNGOracleState {
        uint256 lastPrice;
        uint256 emaPrice;
    }

    constructor(address pool_, uint256 maxCoinsToScan_, uint256 dustTolerance_, uint256 virtualPriceTolerance_) {
        pool = pool_;
        maxCoinsToScan = maxCoinsToScan_;
        dustTolerance = dustTolerance_;
        virtualPriceTolerance = virtualPriceTolerance_;
    }

    function _registerStableSwapNGVirtualPriceTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.EXCHANGE);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.EXCHANGE_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.EXCHANGE_RECEIVED);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.EXCHANGE_RECEIVED_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.EXCHANGE_UNDERLYING);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.EXCHANGE_UNDERLYING_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.ADD_LIQUIDITY_DYNAMIC);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.ADD_LIQUIDITY_DYNAMIC_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.ADD_LIQUIDITY_META);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.ADD_LIQUIDITY_META_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_LIQUIDITY_DYNAMIC);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_LIQUIDITY_DYNAMIC_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_LIQUIDITY_DYNAMIC_RECEIVER_CLAIM);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_LIQUIDITY_META);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_LIQUIDITY_META_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_LIQUIDITY_META_RECEIVER_CLAIM);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_ONE);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_ONE_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_IMBALANCE_DYNAMIC);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_IMBALANCE_DYNAMIC_RECEIVER);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_IMBALANCE_META);
        registerFnCallTrigger(assertionSelector, StableSwapNGSelectors.REMOVE_IMBALANCE_META_RECEIVER);
    }

    function _stableSwapCoinCountAt(PhEvm.ForkId memory fork) internal view returns (uint256 coinCount) {
        coinCount = _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.N_COINS, ()), fork);
        require(coinCount <= maxCoinsToScan, "StableSwapNG: too many coins");
    }

    function _stableSwapCoinAt(uint256 i, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(pool, abi.encodeCall(IStableSwapNGPool.coins, (i)), fork);
    }

    function _stableSwapCoinAccountingAt(uint256 i, PhEvm.ForkId memory fork)
        internal
        view
        returns (StableSwapNGCoinAccounting memory accounting)
    {
        accounting.coin = _stableSwapCoinAt(i, fork);
        accounting.lpBalance = _stableSwapBalanceAt(i, fork);
        accounting.adminBalance = _stableSwapAdminBalanceAt(i, fork);
        accounting.accounted = accounting.lpBalance + accounting.adminBalance;
        accounting.actual = _readBalanceAt(accounting.coin, pool, fork);
    }

    function _stableSwapBalanceAt(uint256 i, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.balances, (i)), fork);
    }

    function _stableSwapAdminBalanceAt(uint256 i, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.admin_balances, (i)), fork);
    }

    function _stableSwapTotalSupplyAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.totalSupply, ()), fork);
    }

    function _stableSwapVirtualPriceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.get_virtual_price, ()), fork);
    }

    function _stableSwapFeeStateAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (StableSwapNGFeeState memory feeState)
    {
        feeState.fee = _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.fee, ()), fork);
        feeState.offpegFeeMultiplier =
            _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.offpeg_fee_multiplier, ()), fork);
    }

    function _stableSwapDynamicFeeAt(uint256 i, uint256 j, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return
            _readUintAt(
                pool, abi.encodeCall(IStableSwapNGPool.dynamic_fee, (int128(int256(i)), int128(int256(j)))), fork
            );
    }

    function _stableSwapOracleStateAt(uint256 i, PhEvm.ForkId memory fork)
        internal
        view
        returns (StableSwapNGOracleState memory oracleState)
    {
        oracleState.lastPrice = _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.last_price, (i)), fork);
        oracleState.emaPrice = _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.ema_price, (i)), fork);
    }

    function _stableSwapDOracleAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.D_oracle, ()), fork);
    }

    function _stableSwapRatesHashAt(PhEvm.ForkId memory fork) internal view returns (bytes32) {
        uint256[] memory rates =
            abi.decode(_viewAt(pool, abi.encodeCall(IStableSwapNGPool.stored_rates, ()), fork), (uint256[]));
        return keccak256(abi.encode(rates));
    }

    function _stableSwapAPreciseAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(IStableSwapNGPool.A_precise, ()), fork);
    }

    function _stableSwapBasePoolAt(PhEvm.ForkId memory fork) internal view returns (bool ok, address basePool) {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(pool, abi.encodeCall(IStableSwapNGMetaPool.BASE_POOL, ()), FORK_VIEW_GAS, fork);
        if (result.ok && result.data.length >= 32) {
            basePool = abi.decode(result.data, (address));
            ok = basePool != address(0);
        }
    }

    function _stableSwapStoredRatesAt(PhEvm.ForkId memory fork) internal view returns (uint256[] memory rates) {
        rates = abi.decode(_viewAt(pool, abi.encodeCall(IStableSwapNGPool.stored_rates, ()), fork), (uint256[]));
    }

    function _stableSwapBasePoolVirtualPriceAt(address basePool, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(basePool, abi.encodeCall(IStableSwapNGPool.get_virtual_price, ()), fork);
    }

    function _stableSwapCanCheckVirtualPrice(PhEvm.ForkId memory beforeFork, PhEvm.ForkId memory afterFork)
        internal
        view
        returns (bool)
    {
        if (_stableSwapTotalSupplyAt(beforeFork) == 0 || _stableSwapTotalSupplyAt(afterFork) == 0) {
            return false;
        }
        if (_stableSwapRatesHashAt(beforeFork) != _stableSwapRatesHashAt(afterFork)) {
            return false;
        }
        return _stableSwapAPreciseAt(beforeFork) == _stableSwapAPreciseAt(afterFork);
    }

    function _stableSwapFeeCapHolds(uint256 fee, uint256 multiplier) internal pure returns (bool) {
        if (fee > MAX_FEE) {
            return false;
        }
        if (fee == 0) {
            return true;
        }
        return multiplier <= (MAX_FEE * FEE_DENOMINATOR) / fee;
    }
}
