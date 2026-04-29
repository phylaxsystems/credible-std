// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";

interface ITriCryptoNGPool {
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function virtual_price() external view returns (uint256);
    function xcp_profit() external view returns (uint256);
    function xcp_profit_a() external view returns (uint256);
    function price_oracle(uint256 k) external view returns (uint256);
    function last_prices(uint256 k) external view returns (uint256);
    function price_scale(uint256 k) external view returns (uint256);
    function fee() external view returns (uint256);
    function mid_fee() external view returns (uint256);
    function out_fee() external view returns (uint256);
    function fee_gamma() external view returns (uint256);
    function A() external view returns (uint256);
    function gamma() external view returns (uint256);
}

library TriCryptoNGSelectors {
    bytes4 internal constant EXCHANGE = bytes4(keccak256("exchange(uint256,uint256,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_RECEIVER = bytes4(keccak256("exchange(uint256,uint256,uint256,uint256,address)"));
    bytes4 internal constant WETH_EXCHANGE_USE_ETH =
        bytes4(keccak256("exchange(uint256,uint256,uint256,uint256,bool)"));
    bytes4 internal constant WETH_EXCHANGE_USE_ETH_RECEIVER =
        bytes4(keccak256("exchange(uint256,uint256,uint256,uint256,bool,address)"));
    bytes4 internal constant EXCHANGE_RECEIVED =
        bytes4(keccak256("exchange_received(uint256,uint256,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_RECEIVED_RECEIVER =
        bytes4(keccak256("exchange_received(uint256,uint256,uint256,uint256,address)"));
    bytes4 internal constant EXCHANGE_UNDERLYING =
        bytes4(keccak256("exchange_underlying(uint256,uint256,uint256,uint256)"));
    bytes4 internal constant EXCHANGE_UNDERLYING_RECEIVER =
        bytes4(keccak256("exchange_underlying(uint256,uint256,uint256,uint256,address)"));
    bytes4 internal constant EXCHANGE_EXTENDED =
        bytes4(keccak256("exchange_extended(uint256,uint256,uint256,uint256,bool,address,address,bytes32)"));

    bytes4 internal constant ADD_LIQUIDITY = bytes4(keccak256("add_liquidity(uint256[3],uint256)"));
    bytes4 internal constant ADD_LIQUIDITY_RECEIVER = bytes4(keccak256("add_liquidity(uint256[3],uint256,address)"));
    bytes4 internal constant WETH_ADD_LIQUIDITY_USE_ETH = bytes4(keccak256("add_liquidity(uint256[3],uint256,bool)"));
    bytes4 internal constant WETH_ADD_LIQUIDITY_USE_ETH_RECEIVER =
        bytes4(keccak256("add_liquidity(uint256[3],uint256,bool,address)"));

    bytes4 internal constant REMOVE_LIQUIDITY = bytes4(keccak256("remove_liquidity(uint256,uint256[3])"));
    bytes4 internal constant REMOVE_LIQUIDITY_RECEIVER =
        bytes4(keccak256("remove_liquidity(uint256,uint256[3],address)"));
    bytes4 internal constant WETH_REMOVE_LIQUIDITY_USE_ETH =
        bytes4(keccak256("remove_liquidity(uint256,uint256[3],bool)"));
    bytes4 internal constant WETH_REMOVE_LIQUIDITY_USE_ETH_RECEIVER =
        bytes4(keccak256("remove_liquidity(uint256,uint256[3],bool,address)"));
    bytes4 internal constant WETH_REMOVE_LIQUIDITY_USE_ETH_RECEIVER_CLAIM =
        bytes4(keccak256("remove_liquidity(uint256,uint256[3],bool,address,bool)"));

    bytes4 internal constant REMOVE_ONE = bytes4(keccak256("remove_liquidity_one_coin(uint256,uint256,uint256)"));
    bytes4 internal constant REMOVE_ONE_RECEIVER =
        bytes4(keccak256("remove_liquidity_one_coin(uint256,uint256,uint256,address)"));
    bytes4 internal constant WETH_REMOVE_ONE_USE_ETH =
        bytes4(keccak256("remove_liquidity_one_coin(uint256,uint256,uint256,bool)"));
    bytes4 internal constant WETH_REMOVE_ONE_USE_ETH_RECEIVER =
        bytes4(keccak256("remove_liquidity_one_coin(uint256,uint256,uint256,bool,address)"));
}

abstract contract TriCryptoNGProtocolHelpers is Assertion {
    uint256 internal constant N_COINS = 3;
    uint256 internal constant N_PRICE_PAIRS = 2;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MIN_FEE = 5e5;
    uint256 internal constant MAX_FEE = 1e10;

    address internal immutable pool;
    address internal immutable wrappedNativeToken;
    uint256 internal immutable dustTolerance;
    uint256 internal immutable virtualPriceToleranceBps;
    uint256 internal immutable profitTolerance;

    struct TriCryptoNGCoinAccounting {
        address coin;
        bool shouldCheckCustody;
        uint256 accounted;
        uint256 actual;
    }

    struct TriCryptoNGFeeState {
        uint256 fee;
        uint256 midFee;
        uint256 outFee;
        uint256 feeGamma;
    }

    struct TriCryptoNGOracleState {
        uint256 priceScale;
        uint256 priceOracle;
        uint256 lastPrice;
    }

    struct TriCryptoNGProfitState {
        uint256 totalSupply;
        uint256 cachedVirtualPrice;
        uint256 liveVirtualPrice;
        uint256 xcpProfit;
        uint256 xcpProfitA;
    }

    constructor(
        address pool_,
        address wrappedNativeToken_,
        uint256 dustTolerance_,
        uint256 virtualPriceToleranceBps_,
        uint256 profitTolerance_
    ) {
        pool = pool_;
        wrappedNativeToken = wrappedNativeToken_;
        dustTolerance = dustTolerance_;
        virtualPriceToleranceBps = virtualPriceToleranceBps_;
        profitTolerance = profitTolerance_;
    }

    function _registerTriCryptoVirtualPriceTriggers(bytes4 assertionSelector) internal view {
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_EXCHANGE_USE_ETH);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_EXCHANGE_USE_ETH_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE_RECEIVED);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE_RECEIVED_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE_UNDERLYING);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE_UNDERLYING_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.EXCHANGE_EXTENDED);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.ADD_LIQUIDITY);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.ADD_LIQUIDITY_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_ADD_LIQUIDITY_USE_ETH);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_ADD_LIQUIDITY_USE_ETH_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.REMOVE_LIQUIDITY);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.REMOVE_LIQUIDITY_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_REMOVE_LIQUIDITY_USE_ETH);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_REMOVE_LIQUIDITY_USE_ETH_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_REMOVE_LIQUIDITY_USE_ETH_RECEIVER_CLAIM);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.REMOVE_ONE);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.REMOVE_ONE_RECEIVER);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_REMOVE_ONE_USE_ETH);
        registerFnCallTrigger(assertionSelector, TriCryptoNGSelectors.WETH_REMOVE_ONE_USE_ETH_RECEIVER);
    }

    function _triCryptoCoinAt(uint256 i, PhEvm.ForkId memory fork) internal view returns (address) {
        return _readAddressAt(pool, abi.encodeCall(ITriCryptoNGPool.coins, (i)), fork);
    }

    function _triCryptoBalanceAt(uint256 i, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.balances, (i)), fork);
    }

    function _triCryptoCoinAccountingAt(uint256 i, PhEvm.ForkId memory fork)
        internal
        view
        returns (TriCryptoNGCoinAccounting memory accounting)
    {
        accounting.coin = _triCryptoCoinAt(i, fork);
        accounting.shouldCheckCustody = accounting.coin != wrappedNativeToken || wrappedNativeToken == address(0);
        accounting.accounted = _triCryptoBalanceAt(i, fork);
        if (accounting.shouldCheckCustody) {
            accounting.actual = _readBalanceAt(accounting.coin, pool, fork);
        }
    }

    function _triCryptoTotalSupplyAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.totalSupply, ()), fork);
    }

    function _triCryptoLiveVirtualPriceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.get_virtual_price, ()), fork);
    }

    function _triCryptoCachedVirtualPriceAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.virtual_price, ()), fork);
    }

    function _triCryptoXcpProfitAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.xcp_profit, ()), fork);
    }

    function _triCryptoXcpProfitAAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.xcp_profit_a, ()), fork);
    }

    function _triCryptoFeeStateAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (TriCryptoNGFeeState memory feeState)
    {
        feeState.fee = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.fee, ()), fork);
        feeState.midFee = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.mid_fee, ()), fork);
        feeState.outFee = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.out_fee, ()), fork);
        feeState.feeGamma = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.fee_gamma, ()), fork);
    }

    function _triCryptoOracleStateAt(uint256 k, PhEvm.ForkId memory fork)
        internal
        view
        returns (TriCryptoNGOracleState memory oracleState)
    {
        oracleState.priceScale = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.price_scale, (k)), fork);
        oracleState.priceOracle = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.price_oracle, (k)), fork);
        oracleState.lastPrice = _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.last_prices, (k)), fork);
    }

    function _triCryptoProfitStateAt(PhEvm.ForkId memory fork)
        internal
        view
        returns (TriCryptoNGProfitState memory profitState)
    {
        profitState.totalSupply = _triCryptoTotalSupplyAt(fork);
        profitState.cachedVirtualPrice = _triCryptoCachedVirtualPriceAt(fork);
        profitState.liveVirtualPrice = _triCryptoLiveVirtualPriceAt(fork);
        profitState.xcpProfit = _triCryptoXcpProfitAt(fork);
        profitState.xcpProfitA = _triCryptoXcpProfitAAt(fork);
    }

    function _triCryptoAAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.A, ()), fork);
    }

    function _triCryptoGammaAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(pool, abi.encodeCall(ITriCryptoNGPool.gamma, ()), fork);
    }

    function _triCryptoCanCheckVirtualPrice(PhEvm.ForkId memory beforeFork, PhEvm.ForkId memory afterFork)
        internal
        view
        returns (bool)
    {
        if (_triCryptoTotalSupplyAt(beforeFork) == 0 || _triCryptoTotalSupplyAt(afterFork) == 0) {
            return false;
        }
        if (_triCryptoXcpProfitAAt(beforeFork) != _triCryptoXcpProfitAAt(afterFork)) {
            return false;
        }
        if (_triCryptoAAt(beforeFork) != _triCryptoAAt(afterFork)) {
            return false;
        }
        return _triCryptoGammaAt(beforeFork) == _triCryptoGammaAt(afterFork);
    }

    function _gteWithAbsoluteTolerance(uint256 value, uint256 floor, uint256 tolerance) internal pure returns (bool) {
        return value + tolerance >= floor;
    }

    function _withinBps(uint256 a, uint256 b, uint256 toleranceBps) internal view returns (bool) {
        if (a == b) {
            return true;
        }
        if (a == 0 || b == 0) {
            return false;
        }

        return ph.ratioGe(a, 1, b, 1, toleranceBps) && ph.ratioGe(b, 1, a, 1, toleranceBps);
    }
}
