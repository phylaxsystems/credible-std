// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {PerpetualProtectionSuiteBase} from "../PerpetualBaseAssertion.sol";
import {IDenariaPerpPairLike, IDenariaVaultLike} from "./DenariaInterfaces.sol";

/// @title DenariaHelpers
/// @author Phylax Systems
/// @notice Shared Denaria protocol reads, log decoders, and utility helpers for the example suite.
abstract contract DenariaHelpers is PerpetualProtectionSuiteBase {
    struct DenariaAccountMetrics {
        address account;
        uint256 price;
        uint256 collateral;
        uint256 maintenanceThreshold;
        uint256 maxLpLeverage;
        uint256 balanceStable;
        uint256 balanceAsset;
        uint256 debtStable;
        uint256 debtAsset;
        uint256 storedFundingFee;
        bool storedFundingFeeSign;
        uint256 pendingFundingFee;
        bool pendingFundingFeeSign;
        int256 storedFundingContribution;
        int256 pendingFundingContribution;
        int256 totalFundingContribution;
        uint256 lpStableBalance;
        uint256 lpAssetBalance;
        uint256 lpDebtStable;
        uint256 lpDebtAsset;
        uint256 openAssetExposure;
        uint256 openNotional;
        uint256 lpLeverageDebtValue;
        int256 runtimePnl;
        int256 runtimeEquity;
        int256 markPnl;
        int256 markEquity;
        uint256 markMarginRatio;
        bool lpLeverageHealthy;
    }

    struct DenariaExecutedTradeLog {
        address user;
        bool direction;
        uint256 tradeSize;
        uint256 tradeReturn;
        uint256 currentPrice;
        uint256 leverage;
    }

    struct DenariaLiquidationLog {
        address user;
        address liquidator;
        uint256 fraction;
        uint256 liquidationFee;
        uint256 positionSize;
        uint256 currentPrice;
        int256 deltaPnl;
        bool liquidationDirection;
    }

    struct DenariaLiquidityMoveLog {
        address user;
        uint256 liquidityStable;
        uint256 liquidityAsset;
        uint256 stableShares;
        uint256 assetShares;
        uint256 feeValue;
        bool added;
    }

    bytes32 internal constant EXECUTED_TRADE_TOPIC0 =
        keccak256("ExecutedTrade(address,bool,uint256,uint256,uint256,uint256)");
    bytes32 internal constant LIQUIDATED_USER_TOPIC0 =
        keccak256("LiquidatedUser(address,address,uint256,uint256,uint256,uint256,int256,bool)");
    bytes32 internal constant LIQUIDITY_MOVED_TOPIC0 =
        keccak256("LiquidityMoved(address,uint256,uint256,uint256,uint256,uint256,bool)");

    uint256 internal constant ORACLE_PRICE_DECIMALS = 1e8;
    uint256 internal constant MARGIN_RATIO_DECIMALS = 1e6;

    address internal immutable PERP_PAIR;
    address internal immutable VAULT;

    constructor(address perpPair_, address vault_) {
        PERP_PAIR = perpPair_;
        VAULT = vault_;
    }

    function _readAccountMetrics(address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (DenariaAccountMetrics memory metrics)
    {
        metrics.account = account;
        metrics.price = _readPrice(fork);
        metrics.collateral = _readCollateral(account, fork);
        metrics.maintenanceThreshold = _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.MMR, ()), fork);
        metrics.maxLpLeverage = _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.maxLpLeverage, ()), fork);

        (
            metrics.balanceStable,
            metrics.balanceAsset,
            metrics.debtStable,
            metrics.debtAsset,
            metrics.storedFundingFee,
            metrics.storedFundingFeeSign,,
        ) =
            abi.decode(
                _viewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.userVirtualTraderPosition, (account)), fork),
                (uint256, uint256, uint256, uint256, uint256, bool, uint256, bool)
            );

        (,, metrics.lpDebtStable, metrics.lpDebtAsset) = abi.decode(
            _viewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.liquidityPosition, (account)), fork),
            (uint256, uint256, uint256, uint256)
        );

        (metrics.lpStableBalance, metrics.lpAssetBalance) = abi.decode(
            _viewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.getLpLiquidityBalance, (account)), fork),
            (uint256, uint256)
        );

        (metrics.pendingFundingFee, metrics.pendingFundingFeeSign) = abi.decode(
            _viewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.computeFundingFee, (account)), fork), (uint256, bool)
        );

        (uint256 pnlMagnitude, bool pnlSign) = abi.decode(
            _viewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.calcPnL, (account, metrics.price)), fork),
            (uint256, bool)
        );

        metrics.runtimePnl = _signedPnl(pnlMagnitude, pnlSign);
        metrics.storedFundingContribution =
            _signedFundingContribution(metrics.storedFundingFee, metrics.storedFundingFeeSign);
        metrics.pendingFundingContribution =
            _signedFundingContribution(metrics.pendingFundingFee, metrics.pendingFundingFeeSign);
        metrics.totalFundingContribution = metrics.storedFundingContribution + metrics.pendingFundingContribution;
        metrics.openAssetExposure =
            _absoluteDifference(metrics.balanceAsset + metrics.lpAssetBalance, metrics.debtAsset + metrics.lpDebtAsset);
        metrics.openNotional = ph.mulDivDown(metrics.openAssetExposure, metrics.price, ORACLE_PRICE_DECIMALS);
        metrics.markPnl = _computeMarkPnl(metrics);
        metrics.runtimeEquity = _toInt256(metrics.collateral) + metrics.runtimePnl;
        metrics.markEquity = _toInt256(metrics.collateral) + metrics.markPnl;
        metrics.markMarginRatio = _computeMarginRatio(metrics.markEquity, metrics.openNotional);
        metrics.lpLeverageDebtValue = _computeLpLeverageDebtValue(metrics);
        metrics.lpLeverageHealthy = _isLpLeverageHealthy(metrics);
    }

    function _readPrice(PhEvm.ForkId memory fork) internal view returns (uint256 price) {
        return _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.getPrice, ()), fork);
    }

    function _readCollateral(address account, PhEvm.ForkId memory fork) internal view returns (uint256 collateral) {
        return _readUintAt(VAULT, abi.encodeCall(IDenariaVaultLike.userCollateral, (account)), fork);
    }

    function _readSignedInsuranceFund(PhEvm.ForkId memory fork) internal view returns (int256 signedInsuranceFund) {
        uint256 amount = _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.insuranceFund, ()), fork);
        bool sign = _readBoolAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.insuranceFundSign, ()), fork);
        return sign ? _toInt256(amount) : -_toInt256(amount);
    }

    function _getExecutedTrades(PhEvm.ForkId memory fork)
        internal
        view
        returns (DenariaExecutedTradeLog[] memory trades)
    {
        PhEvm.Log[] memory logs =
            ph.getLogsQuery(PhEvm.LogQuery({emitter: PERP_PAIR, signature: EXECUTED_TRADE_TOPIC0}), fork);
        trades = new DenariaExecutedTradeLog[](logs.length);

        for (uint256 i; i < logs.length; ++i) {
            trades[i].user = _topicAddress(logs[i].topics[1]);
            (
                trades[i].direction,
                trades[i].tradeSize,
                trades[i].tradeReturn,
                trades[i].currentPrice,
                trades[i].leverage
            ) = abi.decode(logs[i].data, (bool, uint256, uint256, uint256, uint256));
        }
    }

    function _countTradesForAccount(DenariaExecutedTradeLog[] memory trades, address account)
        internal
        pure
        returns (uint256 count)
    {
        for (uint256 i; i < trades.length; ++i) {
            if (trades[i].user == account && trades[i].tradeSize != 0 && trades[i].tradeReturn != 0) {
                ++count;
            }
        }
    }

    function _getLastLiquidation(PhEvm.ForkId memory fork)
        internal
        view
        returns (bool found, DenariaLiquidationLog memory liquidationLog)
    {
        PhEvm.Log[] memory logs =
            ph.getLogsQuery(PhEvm.LogQuery({emitter: PERP_PAIR, signature: LIQUIDATED_USER_TOPIC0}), fork);
        if (logs.length == 0) {
            return (false, liquidationLog);
        }

        PhEvm.Log memory log = logs[logs.length - 1];
        liquidationLog.user = _topicAddress(log.topics[1]);
        (
            liquidationLog.liquidator,
            liquidationLog.fraction,
            liquidationLog.liquidationFee,
            liquidationLog.positionSize,
            liquidationLog.currentPrice,
            liquidationLog.deltaPnl,
            liquidationLog.liquidationDirection
        ) = abi.decode(log.data, (address, uint256, uint256, uint256, uint256, int256, bool));
        return (true, liquidationLog);
    }

    function _getLastLiquidityRemovalForAccount(address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool found, DenariaLiquidityMoveLog memory liquidityMove)
    {
        PhEvm.Log[] memory logs =
            ph.getLogsQuery(PhEvm.LogQuery({emitter: PERP_PAIR, signature: LIQUIDITY_MOVED_TOPIC0}), fork);

        for (uint256 i = logs.length; i != 0; --i) {
            PhEvm.Log memory log = logs[i - 1];
            liquidityMove.user = _topicAddress(log.topics[1]);
            (
                liquidityMove.liquidityStable,
                liquidityMove.liquidityAsset,
                liquidityMove.stableShares,
                liquidityMove.assetShares,
                liquidityMove.feeValue,
                liquidityMove.added
            ) = abi.decode(log.data, (uint256, uint256, uint256, uint256, uint256, bool));

            if (liquidityMove.user == account && !liquidityMove.added) {
                return (true, liquidityMove);
            }
        }
    }

    function _computeMarginRatio(int256 equity, uint256 openNotional) internal pure returns (uint256 marginRatio) {
        if (equity < 0) {
            return 0;
        }
        if (openNotional == 0) {
            return MARGIN_RATIO_DECIMALS;
        }
        return _toUint256(equity) * MARGIN_RATIO_DECIMALS / openNotional;
    }

    function _isLpLeverageHealthy(DenariaAccountMetrics memory metrics) internal pure returns (bool) {
        if (metrics.lpStableBalance + metrics.lpAssetBalance == 0) {
            return true;
        }

        return metrics.collateral * metrics.maxLpLeverage >= metrics.lpLeverageDebtValue;
    }

    function _hasTrackedState(DenariaAccountMetrics memory metrics) internal pure returns (bool) {
        return metrics.balanceStable != 0 || metrics.balanceAsset != 0 || metrics.debtStable != 0
            || metrics.debtAsset != 0 || metrics.lpStableBalance != 0 || metrics.lpAssetBalance != 0
            || metrics.lpDebtStable != 0 || metrics.lpDebtAsset != 0;
    }

    function _absoluteDifference(uint256 left, uint256 right) internal pure returns (uint256 difference) {
        return left >= right ? left - right : right - left;
    }

    function _signedPnl(uint256 magnitude, bool pnlSign) internal pure returns (int256 signedPnl) {
        int256 signedMagnitude = _toInt256(magnitude);
        return pnlSign ? signedMagnitude : -signedMagnitude;
    }

    function _signedFundingContribution(uint256 magnitude, bool fundingFeeSign)
        internal
        pure
        returns (int256 signedFunding)
    {
        int256 signedMagnitude = _toInt256(magnitude);
        return fundingFeeSign ? -signedMagnitude : signedMagnitude;
    }

    function _computeMarkPnl(DenariaAccountMetrics memory metrics) internal pure returns (int256 markPnl) {
        int256 stableSide = _toInt256(metrics.balanceStable + metrics.lpStableBalance)
            - _toInt256(metrics.debtStable + metrics.lpDebtStable);
        int256 assetSide = _toInt256(metrics.balanceAsset + metrics.lpAssetBalance)
            - _toInt256(metrics.debtAsset + metrics.lpDebtAsset);

        return stableSide + metrics.totalFundingContribution + _markAssetContribution(assetSide, metrics.price);
    }

    function _computeLpLeverageDebtValue(DenariaAccountMetrics memory metrics)
        internal
        pure
        returns (uint256 totalDebtValue)
    {
        if (metrics.lpStableBalance + metrics.lpAssetBalance == 0) {
            return 0;
        }

        uint256 traderNetStableDebt =
            metrics.debtStable > metrics.balanceStable ? metrics.debtStable - metrics.balanceStable : 0;
        uint256 traderNetAssetDebt =
            metrics.debtAsset > metrics.balanceAsset ? metrics.debtAsset - metrics.balanceAsset : 0;
        return traderNetStableDebt + metrics.lpDebtStable
            + _mulDivDown(traderNetAssetDebt + metrics.lpDebtAsset, metrics.price, ORACLE_PRICE_DECIMALS);
    }

    function _markAssetContribution(int256 assetDelta, uint256 price) internal pure returns (int256 contribution) {
        if (assetDelta == 0) {
            return 0;
        }

        if (assetDelta > 0) {
            return _toInt256(_toUint256(assetDelta) * price / ORACLE_PRICE_DECIMALS);
        }

        return -_toInt256(_toUint256(-assetDelta) * price / ORACLE_PRICE_DECIMALS);
    }

    function _lpLeverageCapacity(DenariaAccountMetrics memory metrics) internal pure returns (int256 capacity) {
        return _toInt256(metrics.collateral * metrics.maxLpLeverage) - _toInt256(metrics.lpLeverageDebtValue);
    }

    function _decreaseBetween(int256 beforeValue, int256 afterValue) internal pure returns (uint256 decrease) {
        return afterValue < beforeValue ? _toUint256(beforeValue - afterValue) : 0;
    }

    function _topicAddress(bytes32 topic) internal pure returns (address account) {
        return address(uint160(uint256(topic)));
    }

    function _toInt256(uint256 value) internal pure returns (int256 signedValue) {
        if (value > uint256(type(int256).max)) {
            return type(int256).max;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }

    function _toUint256(int256 value) internal pure returns (uint256 unsignedValue) {
        require(value >= 0, "negative int");
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(value);
    }

    function _mulDivDown(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        return x * y / denominator;
    }
}
