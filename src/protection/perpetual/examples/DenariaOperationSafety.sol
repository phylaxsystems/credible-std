// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {IPerpetualProtectionSuite} from "../IPerpetualProtectionSuite.sol";
import {PerpetualBaseAssertion} from "../PerpetualBaseAssertion.sol";
import {PerpetualProtectionSuiteBase} from "../PerpetualProtectionSuiteBase.sol";

/// @notice Minimal Denaria perp-pair surface used by the example suite.
/// @dev Derived against `~/Documents/code/solidity/denaria-perp-main/`.
interface IDenariaPerpPairLike {
    function trade(
        bool direction,
        uint256 size,
        uint256 minTradeReturn,
        uint256 initialGuess,
        address frontendAddress,
        uint8 leverage,
        bytes memory unverifiedReport
    ) external returns (uint256);

    function closeAndWithdraw(
        uint256 maxSlippage,
        uint256 maxLiqFee,
        address frontendAddress,
        bytes memory unverifiedReport
    ) external;

    function addLiquidity(
        uint256 liquidityStable,
        uint256 liquidityAsset,
        uint256 maxFeeValue,
        bytes memory unverifiedReport
    ) external;

    function removeLiquidity(
        uint256 liquidityStableToRemove,
        uint256 liquidityAssetToRemove,
        uint256 maxFeeValue,
        bytes memory unverifiedReport
    ) external;

    function realizePnL(bytes calldata unverifiedReport) external returns (uint256, bool);
    function liquidate(address user, uint256 liquidatedPositionSize, bytes memory unverifiedReport) external;
    function getPrice() external view returns (uint256);
    function calcPnL(address user, uint256 price) external view returns (uint256, bool);
    function computeFundingFee(address user) external view returns (uint256, bool);
    function getLpLiquidityBalance(address user) external view returns (uint256, uint256);
    function MMR() external view returns (uint256);
    function maxLpLeverage() external view returns (uint256);
    function globalLiquidityStable() external view returns (uint256);
    function globalLiquidityAsset() external view returns (uint256);
    function insuranceFund() external view returns (uint256);
    function insuranceFundSign() external view returns (bool);

    function userVirtualTraderPosition(address user)
        external
        view
        returns (
            uint256 balanceStable,
            uint256 balanceAsset,
            uint256 debtStable,
            uint256 debtAsset,
            uint256 fundingFee,
            bool fundingFeeSign,
            uint256 initialFundingRate,
            bool initialFundingRateSign
        );

    function liquidityPosition(address user)
        external
        view
        returns (uint256 initialStableShares, uint256 initialAssetShares, uint256 debtStable, uint256 debtAsset);
}

/// @notice Minimal Denaria vault surface used by the example suite.
interface IDenariaVaultLike {
    function removeCollateral(uint256 amount, bytes memory unverifiedReport) external;
    function removeAllCollateral(bytes memory unverifiedReport) external;
    function userCollateral(address user) external view returns (uint256);
}

/// @title DenariaProtectionSuite
/// @author Phylax Systems
/// @notice Example `IPerpetualProtectionSuite` for the Denaria perpetual protocol.
/// @dev This example is intentionally written in the same style as the Aave v3 lending example:
///      - it is self-contained inside `credible-std`
///      - it defines the minimal Denaria interfaces it needs locally
///      - it exposes a single generic assertion bundle that can be registered against both the
///        `PerpPair` and the `Vault`
///
///      The example focuses on the Denaria invariants that fit the generic perpetual suite well:
///      - non-liquidation operations must not create self bad debt
///      - non-liquidation operations must leave the account healthy at mark
///      - trade execution must be no better than the protocol mark price
///      - successful trades must stay backed by available side liquidity
///      - liquidation is only permitted from an unhealthy pre-state
///      - critical execution prices must stay oracle-anchored
contract DenariaProtectionSuite is PerpetualProtectionSuiteBase {
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

    bytes32 internal constant MARGIN_RATIO_METRIC = "MARGIN_RATIO";
    bytes32 internal constant EQUITY_METRIC = "EQUITY";
    bytes32 internal constant LP_LEVERAGE_CAPACITY_METRIC = "LP_LEVERAGE_CAPACITY";
    bytes32 internal constant TAKER_WORSE_THAN_MARK = "TAKER_WORSE_THAN_MARK";
    bytes32 internal constant TRADE_LIQUIDITY_COVERAGE = "TRADE_LIQUIDITY_COVERAGE";
    bytes32 internal constant LIQUIDATION_GATED_BY_MMR = "LIQUIDATION_GATED_BY_MMR";
    bytes32 internal constant RISK_MARK_ANCHORED = "RISK_MARK_ANCHORED";

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

    /// @notice Returns the Denaria selectors that feed the shared perpetual assertions.
    /// @dev Register the bundled assertion against both the `PerpPair` and the `Vault` to cover the
    ///      full non-liquidation user surface that can affect perpetual risk.
    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IDenariaPerpPairLike.trade.selector;
        selectors[1] = IDenariaPerpPairLike.closeAndWithdraw.selector;
        selectors[2] = IDenariaPerpPairLike.addLiquidity.selector;
        selectors[3] = IDenariaPerpPairLike.removeLiquidity.selector;
        selectors[4] = IDenariaPerpPairLike.realizePnL.selector;
        selectors[5] = IDenariaPerpPairLike.liquidate.selector;
        selectors[6] = IDenariaVaultLike.removeCollateral.selector;
        selectors[7] = IDenariaVaultLike.removeAllCollateral.selector;
    }

    /// @notice Decodes Denaria PerpPair and Vault calls into the shared perpetual operation model.
    function decodeOperation(TriggeredCall calldata triggered)
        external
        pure
        override
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == IDenariaPerpPairLike.trade.selector) {
            (
                bool direction,
                uint256 size,
                uint256 minTradeReturn,
                uint256 initialGuess,
                address frontendAddress,
                uint8 leverage,
            ) = abi.decode(triggered.input[4:], (bool, uint256, uint256, uint256, address, uint8, bytes));

            operation.kind = OperationKind.IncreasePosition;
            operation.account = triggered.caller;
            operation.market = triggered.target;
            operation.isLong = direction;
            operation.sizeDelta = size;
            operation.limitPrice = minTradeReturn;
            operation.mutatesExposure = size != 0;
            operation.reducesAccountSafety = true;
            operation.metadata = abi.encode(initialGuess, frontendAddress, leverage);
            return operation;
        }

        if (triggered.selector == IDenariaPerpPairLike.closeAndWithdraw.selector) {
            (uint256 maxSlippage, uint256 maxLiqFee, address frontendAddress,) =
                abi.decode(triggered.input[4:], (uint256, uint256, address, bytes));

            operation.kind = OperationKind.DecreasePosition;
            operation.account = triggered.caller;
            operation.market = triggered.target;
            operation.limitPrice = maxSlippage;
            operation.mutatesExposure = true;
            operation.reducesAccountSafety = true;
            operation.metadata = abi.encode(maxLiqFee, frontendAddress);
            return operation;
        }

        if (triggered.selector == IDenariaPerpPairLike.addLiquidity.selector) {
            (uint256 liquidityStable, uint256 liquidityAsset, uint256 maxFeeValue,) =
                abi.decode(triggered.input[4:], (uint256, uint256, uint256, bytes));

            operation.kind = OperationKind.AddLiquidity;
            operation.account = triggered.caller;
            operation.market = triggered.target;
            operation.sizeDelta = liquidityAsset;
            operation.collateralDelta = _toInt256(liquidityStable);
            operation.mutatesExposure = liquidityStable != 0 || liquidityAsset != 0;
            operation.reducesAccountSafety = true;
            operation.metadata = abi.encode(maxFeeValue);
            return operation;
        }

        if (triggered.selector == IDenariaPerpPairLike.removeLiquidity.selector) {
            (uint256 liquidityStableToRemove, uint256 liquidityAssetToRemove, uint256 maxFeeValue,) =
                abi.decode(triggered.input[4:], (uint256, uint256, uint256, bytes));

            operation.kind = OperationKind.RemoveLiquidity;
            operation.account = triggered.caller;
            operation.market = triggered.target;
            operation.sizeDelta = liquidityAssetToRemove;
            operation.collateralDelta = -_toInt256(liquidityStableToRemove);
            operation.mutatesExposure = liquidityStableToRemove != 0 || liquidityAssetToRemove != 0;
            operation.reducesAccountSafety = true;
            operation.metadata = abi.encode(maxFeeValue);
            return operation;
        }

        if (triggered.selector == IDenariaPerpPairLike.realizePnL.selector) {
            operation.kind = OperationKind.RealizePnL;
            operation.account = triggered.caller;
            operation.market = triggered.target;
            operation.reducesAccountSafety = true;
            return operation;
        }

        if (triggered.selector == IDenariaPerpPairLike.liquidate.selector) {
            (address user, uint256 liquidatedPositionSize,) = abi.decode(triggered.input[4:], (address, uint256, bytes));

            operation.kind = OperationKind.Liquidation;
            operation.account = user;
            operation.market = triggered.target;
            operation.counterparty = triggered.caller;
            operation.sizeDelta = liquidatedPositionSize;
            operation.mutatesExposure = liquidatedPositionSize != 0;
            operation.isLiquidation = true;
            return operation;
        }

        if (triggered.selector == IDenariaVaultLike.removeCollateral.selector) {
            (uint256 amount,) = abi.decode(triggered.input[4:], (uint256, bytes));

            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.market = address(0);
            operation.collateralAsset = triggered.target;
            operation.collateralDelta = -_toInt256(amount);
            operation.reducesAccountSafety = true;
            return operation;
        }

        if (triggered.selector == IDenariaVaultLike.removeAllCollateral.selector) {
            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.market = address(0);
            operation.collateralAsset = triggered.target;
            operation.reducesAccountSafety = true;
            return operation;
        }
    }

    /// @notice Denaria non-liquidation mutations must preserve post-state safety.
    function shouldCheckPostMutationRisk(OperationContext calldata operation)
        external
        pure
        override
        returns (bool shouldCheck)
    {
        return operation.account != address(0) && !operation.isLiquidation && operation.reducesAccountSafety;
    }

    /// @notice Builds Denaria's taker-worse-than-mark execution check for direct `trade(...)` calls.
    function getExecutionPriceChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view override returns (ExecutionPriceCheck[] memory checks) {
        beforeFork;

        if (
            triggered.target != PERP_PAIR
                || (triggered.selector != IDenariaPerpPairLike.trade.selector
                    && triggered.selector != IDenariaPerpPairLike.closeAndWithdraw.selector)
        ) {
            return new ExecutionPriceCheck[](0);
        }

        DenariaExecutedTradeLog[] memory tradeLogs = _getExecutedTrades(afterFork);
        uint256 relevantTrades = _countTradesForAccount(tradeLogs, operation.account);
        if (relevantTrades == 0) {
            return new ExecutionPriceCheck[](0);
        }

        checks = new ExecutionPriceCheck[](relevantTrades);
        uint256 checkIndex;
        for (uint256 i; i < tradeLogs.length; ++i) {
            DenariaExecutedTradeLog memory tradeLog = tradeLogs[i];
            if (tradeLog.user != operation.account || tradeLog.tradeSize == 0 || tradeLog.tradeReturn == 0) {
                continue;
            }

            uint256 executionPrice = tradeLog.direction
                ? ph.mulDivDown(tradeLog.tradeSize, ORACLE_PRICE_DECIMALS, tradeLog.tradeReturn)
                : ph.mulDivDown(tradeLog.tradeReturn, ORACLE_PRICE_DECIMALS, tradeLog.tradeSize);

            checks[checkIndex] = ExecutionPriceCheck({
                checkName: TAKER_WORSE_THAN_MARK,
                account: operation.account,
                market: PERP_PAIR,
                executionPrice: executionPrice,
                minExecutionPrice: tradeLog.direction ? tradeLog.currentPrice : 0,
                maxExecutionPrice: tradeLog.direction ? type(uint256).max : tradeLog.currentPrice,
                metadata: abi.encode(
                    triggered.selector, checkIndex, tradeLog.direction, tradeLog.tradeSize, tradeLog.tradeReturn
                )
            });
            ++checkIndex;
        }
    }

    /// @notice Builds Denaria's side-liquidity coverage check for direct `trade(...)` calls.
    function getLiquidityCoverageChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view override returns (LiquidityCoverageCheck[] memory checks) {
        if (
            triggered.target != PERP_PAIR
                || (triggered.selector != IDenariaPerpPairLike.trade.selector
                    && triggered.selector != IDenariaPerpPairLike.closeAndWithdraw.selector)
        ) {
            return new LiquidityCoverageCheck[](0);
        }

        DenariaExecutedTradeLog[] memory tradeLogs = _getExecutedTrades(afterFork);
        uint256 relevantTrades = _countTradesForAccount(tradeLogs, operation.account);
        if (relevantTrades == 0) {
            return new LiquidityCoverageCheck[](0);
        }

        uint256 currentStableLiquidity =
            _suiteReadUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.globalLiquidityStable, ()), beforeFork);
        uint256 currentAssetLiquidity =
            _suiteReadUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.globalLiquidityAsset, ()), beforeFork);

        if (triggered.selector == IDenariaPerpPairLike.closeAndWithdraw.selector) {
            DenariaAccountMetrics memory beforeMetrics = _readAccountMetrics(operation.account, beforeFork);
            (bool foundRemoval, DenariaLiquidityMoveLog memory removalLog) =
                _getLastLiquidityRemovalForAccount(operation.account, afterFork);

            if (foundRemoval) {
                bool feeDistributed = currentStableLiquidity > beforeMetrics.lpStableBalance
                    && currentAssetLiquidity > beforeMetrics.lpAssetBalance;
                currentStableLiquidity = currentStableLiquidity > beforeMetrics.lpStableBalance
                    ? currentStableLiquidity - beforeMetrics.lpStableBalance
                    : 0;
                if (feeDistributed) {
                    currentStableLiquidity += removalLog.feeValue;
                }
                currentAssetLiquidity = currentAssetLiquidity > beforeMetrics.lpAssetBalance
                    ? currentAssetLiquidity - beforeMetrics.lpAssetBalance
                    : 0;
            }
        }

        checks = new LiquidityCoverageCheck[](relevantTrades);
        uint256 checkIndex;
        for (uint256 i; i < tradeLogs.length; ++i) {
            DenariaExecutedTradeLog memory tradeLog = tradeLogs[i];
            if (tradeLog.user != operation.account || tradeLog.tradeSize == 0 || tradeLog.tradeReturn == 0) {
                continue;
            }

            uint256 availableAmount = tradeLog.direction ? currentAssetLiquidity : currentStableLiquidity;
            checks[checkIndex] = LiquidityCoverageCheck({
                checkName: TRADE_LIQUIDITY_COVERAGE,
                market: PERP_PAIR,
                accountingBucket: PERP_PAIR,
                requiredAmount: tradeLog.tradeReturn,
                availableAmount: availableAmount,
                metadata: abi.encode(triggered.selector, checkIndex, tradeLog.direction, tradeLog.tradeSize)
            });

            if (!tradeLog.direction) {
                currentAssetLiquidity += tradeLog.tradeSize;
            } else {
                currentAssetLiquidity =
                    currentAssetLiquidity > tradeLog.tradeReturn ? currentAssetLiquidity - tradeLog.tradeReturn : 0;
            }

            ++checkIndex;
        }
    }

    /// @notice Builds a Denaria liquidation-gating check from the pre-state margin ratio.
    /// @dev This example intentionally focuses on the liquidation gate itself. The returned metadata
    ///      still exposes the pre/post insurance-fund values for downstream debugging or stronger
    ///      protocol-specific assertions.
    function getLiquidationChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view override returns (LiquidationCheck[] memory checks) {
        if (triggered.target != PERP_PAIR || triggered.selector != IDenariaPerpPairLike.liquidate.selector) {
            return new LiquidationCheck[](0);
        }

        DenariaAccountMetrics memory beforeMetrics = _readAccountMetrics(operation.account, beforeFork);
        uint256 collateralBefore = _readCollateral(operation.account, beforeFork);
        uint256 collateralAfter = _readCollateral(operation.account, afterFork);
        int256 insuranceBefore = _readSignedInsuranceFund(beforeFork);
        int256 insuranceAfter = _readSignedInsuranceFund(afterFork);
        uint256 collateralAbsorbed = _consumedBetween(collateralBefore, collateralAfter);
        uint256 insuranceAbsorbed = _decreaseBetween(insuranceBefore, insuranceAfter);
        uint256 realizedLoss = collateralAbsorbed + insuranceAbsorbed;

        checks = new LiquidationCheck[](1);
        checks[0] = LiquidationCheck({
            checkName: LIQUIDATION_GATED_BY_MMR,
            account: operation.account,
            market: PERP_PAIR,
            wasLiquidatableBefore: beforeMetrics.markMarginRatio <= beforeMetrics.maintenanceThreshold,
            lossCreated: _toInt256(realizedLoss),
            absorbedLoss: realizedLoss,
            absorber: insuranceAbsorbed != 0 ? PERP_PAIR : VAULT,
            metadata: abi.encode(
                beforeMetrics.markMarginRatio,
                beforeMetrics.maintenanceThreshold,
                collateralAbsorbed,
                insuranceBefore,
                insuranceAfter
            )
        });
    }

    /// @notice Builds exact-price oracle-anchor checks from the Denaria trade and liquidation logs.
    function getOracleAnchorChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view override returns (OracleAnchorCheck[] memory checks) {
        beforeFork;

        if (
            triggered.target == PERP_PAIR
                && (triggered.selector == IDenariaPerpPairLike.trade.selector
                    || triggered.selector == IDenariaPerpPairLike.closeAndWithdraw.selector)
        ) {
            DenariaExecutedTradeLog[] memory tradeLogs = _getExecutedTrades(afterFork);
            uint256 relevantTrades = _countTradesForAccount(tradeLogs, operation.account);
            if (relevantTrades == 0) {
                return new OracleAnchorCheck[](0);
            }

            uint256 oraclePrice = _readPrice(afterFork);
            checks = new OracleAnchorCheck[](relevantTrades);
            uint256 checkIndex;
            for (uint256 i; i < tradeLogs.length; ++i) {
                DenariaExecutedTradeLog memory tradeLog = tradeLogs[i];
                if (tradeLog.user != operation.account || tradeLog.tradeSize == 0 || tradeLog.tradeReturn == 0) {
                    continue;
                }

                checks[checkIndex] = OracleAnchorCheck({
                    checkName: RISK_MARK_ANCHORED,
                    market: PERP_PAIR,
                    usedPrice: tradeLog.currentPrice,
                    minOraclePrice: oraclePrice,
                    maxOraclePrice: oraclePrice,
                    metadata: abi.encode(triggered.selector, checkIndex, tradeLog.direction, tradeLog.tradeSize)
                });
                ++checkIndex;
            }
            return checks;
        }

        if (triggered.target == PERP_PAIR && triggered.selector == IDenariaPerpPairLike.liquidate.selector) {
            (bool found, DenariaLiquidationLog memory liquidationLog) = _getLastLiquidation(afterFork);
            if (!found) {
                return new OracleAnchorCheck[](0);
            }

            uint256 oraclePrice = _readPrice(afterFork);
            checks = new OracleAnchorCheck[](1);
            checks[0] = OracleAnchorCheck({
                checkName: RISK_MARK_ANCHORED,
                market: PERP_PAIR,
                usedPrice: liquidationLog.currentPrice,
                minOraclePrice: oraclePrice,
                maxOraclePrice: oraclePrice,
                metadata: abi.encode(liquidationLog.positionSize, liquidationLog.fraction)
            });
        }
    }

    /// @notice Reads and normalizes Denaria's aggregate account state.
    function getAccountState(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountState memory state)
    {
        return _buildAccountState(_readAccountMetrics(account, fork));
    }

    /// @notice Reads Denaria's single-market account position.
    function getAccountPositions(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (PositionState[] memory positions)
    {
        return _buildPositions(_readAccountMetrics(account, fork));
    }

    /// @notice Evaluates Denaria health from mark-to-market equity, margin ratio, and LP leverage.
    function evaluateRisk(AccountState calldata state, PositionState[] calldata positions, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (RiskState memory risk)
    {
        positions;
        risk = _buildGenericRiskState(_readAccountMetrics(state.account, fork));
    }

    /// @notice Optimized snapshot path that avoids rereading Denaria account state three times.
    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountSnapshot memory snapshot)
    {
        DenariaAccountMetrics memory metrics = _readAccountMetrics(account, fork);
        snapshot.state = _buildAccountState(metrics);
        snapshot.positions = _buildPositions(metrics);
        snapshot.risk = _buildGenericRiskState(metrics);
    }

    /// @notice Operation-aware post-mutation snapshot that mirrors Denaria's action-specific guards.
    function getPostMutationSnapshot(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata fork
    ) external view override returns (AccountSnapshot memory snapshot) {
        triggered;

        DenariaAccountMetrics memory metrics = _readAccountMetrics(operation.account, fork);
        snapshot.state = _buildAccountState(metrics);
        snapshot.positions = _buildPositions(metrics);
        snapshot.risk = _buildPostMutationRiskState(metrics, operation);
    }

    function _readAccountMetrics(address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (DenariaAccountMetrics memory metrics)
    {
        metrics.account = account;
        metrics.price = _readPrice(fork);
        metrics.collateral = _readCollateral(account, fork);
        metrics.maintenanceThreshold = _suiteReadUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.MMR, ()), fork);
        metrics.maxLpLeverage =
            _suiteReadUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.maxLpLeverage, ()), fork);

        (
            metrics.balanceStable,
            metrics.balanceAsset,
            metrics.debtStable,
            metrics.debtAsset,
            metrics.storedFundingFee,
            metrics.storedFundingFeeSign,,
        ) =
            abi.decode(
                _suiteViewAt(
                    PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.userVirtualTraderPosition, (account)), fork
                ),
                (uint256, uint256, uint256, uint256, uint256, bool, uint256, bool)
            );

        (,, metrics.lpDebtStable, metrics.lpDebtAsset) = abi.decode(
            _suiteViewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.liquidityPosition, (account)), fork),
            (uint256, uint256, uint256, uint256)
        );

        (metrics.lpStableBalance, metrics.lpAssetBalance) = abi.decode(
            _suiteViewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.getLpLiquidityBalance, (account)), fork),
            (uint256, uint256)
        );

        (metrics.pendingFundingFee, metrics.pendingFundingFeeSign) = abi.decode(
            _suiteViewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.computeFundingFee, (account)), fork),
            (uint256, bool)
        );

        (uint256 pnlMagnitude, bool pnlSign) = abi.decode(
            _suiteViewAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.calcPnL, (account, metrics.price)), fork),
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

    function _buildAccountState(DenariaAccountMetrics memory metrics)
        internal
        pure
        returns (AccountState memory state)
    {
        state.account = metrics.account;
        state.collateralValue = metrics.collateral;
        state.openNotional = metrics.openNotional;
        state.unrealizedPnl = metrics.runtimePnl;
        state.accruedFunding = metrics.totalFundingContribution;
        state.hasOpenExposure = _hasTrackedState(metrics);
        state.metadata = abi.encode(
            metrics.price,
            metrics.runtimeEquity,
            metrics.markEquity,
            metrics.markMarginRatio,
            metrics.maintenanceThreshold,
            metrics.lpLeverageHealthy,
            metrics.maxLpLeverage,
            metrics.lpLeverageDebtValue,
            metrics.lpStableBalance,
            metrics.lpAssetBalance,
            metrics.lpDebtStable,
            metrics.lpDebtAsset
        );
    }

    function _buildPositions(DenariaAccountMetrics memory metrics)
        internal
        view
        returns (PositionState[] memory positions)
    {
        if (!_hasTrackedState(metrics)) {
            return new PositionState[](0);
        }

        positions = new PositionState[](1);
        positions[0] = PositionState({
            market: PERP_PAIR,
            collateralAsset: VAULT,
            isLong: metrics.balanceAsset + metrics.lpAssetBalance >= metrics.debtAsset + metrics.lpDebtAsset,
            size: metrics.openAssetExposure,
            openNotional: metrics.openNotional,
            collateralValue: metrics.collateral,
            pnl: metrics.runtimePnl,
            accruedFunding: metrics.totalFundingContribution,
            markPrice: metrics.price,
            maintenanceRequirement: _mulDivDown(
                metrics.openNotional, metrics.maintenanceThreshold, MARGIN_RATIO_DECIMALS
            ),
            metadata: abi.encode(
                metrics.balanceStable,
                metrics.balanceAsset,
                metrics.debtStable,
                metrics.debtAsset,
                metrics.lpStableBalance,
                metrics.lpAssetBalance,
                metrics.lpDebtStable,
                metrics.lpDebtAsset
            )
        });
    }

    function _buildGenericRiskState(DenariaAccountMetrics memory metrics)
        internal
        pure
        returns (RiskState memory risk)
    {
        risk.isHealthy = metrics.runtimeEquity >= 0 && metrics.markMarginRatio > metrics.maintenanceThreshold;
        risk.hasBadDebt = metrics.runtimeEquity < 0;
        risk.isLiquidatable = metrics.openNotional != 0 && metrics.markMarginRatio <= metrics.maintenanceThreshold;
        risk.metricName = MARGIN_RATIO_METRIC;
        risk.equity = metrics.runtimeEquity;
        risk.metricValue = _toInt256(metrics.markMarginRatio);
        risk.thresholdValue = _toInt256(metrics.maintenanceThreshold);
        risk.comparison = ComparisonKind.Gt;
        risk.metadata = abi.encode(
            metrics.price,
            metrics.collateral,
            metrics.runtimePnl,
            metrics.markPnl,
            metrics.totalFundingContribution,
            metrics.lpLeverageHealthy,
            metrics.maxLpLeverage
        );
    }

    function _buildPostMutationRiskState(DenariaAccountMetrics memory metrics, OperationContext calldata operation)
        internal
        pure
        returns (RiskState memory risk)
    {
        if (operation.kind == OperationKind.IncreasePosition) {
            return _buildMarginRatioRiskState(metrics, ComparisonKind.Gt, false);
        }

        if (operation.kind == OperationKind.WithdrawCollateral) {
            return _buildWithdrawCollateralRiskState(metrics);
        }

        if (operation.kind == OperationKind.AddLiquidity) {
            return _buildLpLeverageRiskState(metrics);
        }

        if (
            operation.kind == OperationKind.DecreasePosition || operation.kind == OperationKind.RemoveLiquidity
                || operation.kind == OperationKind.RealizePnL
        ) {
            return _buildNoBadDebtRiskState(metrics);
        }

        return _buildGenericRiskState(metrics);
    }

    function _buildMarginRatioRiskState(
        DenariaAccountMetrics memory metrics,
        ComparisonKind comparison,
        bool includeLpLeverage
    ) internal pure returns (RiskState memory risk) {
        bool marginHealthy = comparison == ComparisonKind.Gt
            ? metrics.markMarginRatio > metrics.maintenanceThreshold
            : metrics.markMarginRatio >= metrics.maintenanceThreshold;

        risk.isHealthy =
            metrics.runtimeEquity >= 0 && marginHealthy && (!includeLpLeverage || metrics.lpLeverageHealthy);
        risk.hasBadDebt = metrics.runtimeEquity < 0;
        risk.isLiquidatable = metrics.openNotional != 0 && metrics.markMarginRatio <= metrics.maintenanceThreshold;
        risk.metricName = MARGIN_RATIO_METRIC;
        risk.equity = metrics.runtimeEquity;
        risk.metricValue = _toInt256(metrics.markMarginRatio);
        risk.thresholdValue = _toInt256(metrics.maintenanceThreshold);
        risk.comparison = comparison;
        risk.metadata = abi.encode(
            includeLpLeverage,
            metrics.markEquity,
            metrics.runtimePnl,
            metrics.markPnl,
            metrics.lpLeverageHealthy,
            metrics.lpLeverageDebtValue
        );
    }

    function _buildWithdrawCollateralRiskState(DenariaAccountMetrics memory metrics)
        internal
        pure
        returns (RiskState memory risk)
    {
        // Vault._checkMR(...) uses stored funding only when validating collateral withdrawals.
        int256 withdrawMarkPnl = metrics.markPnl - metrics.pendingFundingContribution;
        int256 withdrawMarkEquity = _toInt256(metrics.collateral) + withdrawMarkPnl;
        uint256 withdrawMarkMarginRatio = _computeMarginRatio(withdrawMarkEquity, metrics.openNotional);

        risk.isHealthy =
            metrics.runtimeEquity >= 0 && withdrawMarkMarginRatio >= metrics.maintenanceThreshold
                && metrics.lpLeverageHealthy;
        risk.hasBadDebt = metrics.runtimeEquity < 0;
        risk.isLiquidatable =
            metrics.openNotional != 0 && withdrawMarkMarginRatio <= metrics.maintenanceThreshold;
        risk.metricName = MARGIN_RATIO_METRIC;
        risk.equity = metrics.runtimeEquity;
        risk.metricValue = _toInt256(withdrawMarkMarginRatio);
        risk.thresholdValue = _toInt256(metrics.maintenanceThreshold);
        risk.comparison = ComparisonKind.Gte;
        risk.metadata = abi.encode(
            withdrawMarkEquity,
            withdrawMarkPnl,
            metrics.storedFundingContribution,
            metrics.pendingFundingContribution,
            metrics.lpLeverageHealthy,
            metrics.lpLeverageDebtValue
        );
    }

    function _buildLpLeverageRiskState(DenariaAccountMetrics memory metrics)
        internal
        pure
        returns (RiskState memory risk)
    {
        risk.isHealthy = metrics.runtimeEquity >= 0 && metrics.lpLeverageHealthy;
        risk.hasBadDebt = metrics.runtimeEquity < 0;
        risk.isLiquidatable = metrics.openNotional != 0 && metrics.markMarginRatio <= metrics.maintenanceThreshold;
        risk.metricName = LP_LEVERAGE_CAPACITY_METRIC;
        risk.equity = metrics.runtimeEquity;
        risk.metricValue = _lpLeverageCapacity(metrics);
        risk.thresholdValue = 0;
        risk.comparison = ComparisonKind.Gte;
        risk.metadata =
            abi.encode(metrics.lpLeverageDebtValue, metrics.maxLpLeverage, metrics.collateral, metrics.runtimePnl);
    }

    function _buildNoBadDebtRiskState(DenariaAccountMetrics memory metrics)
        internal
        pure
        returns (RiskState memory risk)
    {
        risk.isHealthy = metrics.runtimeEquity >= 0;
        risk.hasBadDebt = metrics.runtimeEquity < 0;
        risk.isLiquidatable = metrics.openNotional != 0 && metrics.markMarginRatio <= metrics.maintenanceThreshold;
        risk.metricName = EQUITY_METRIC;
        risk.equity = metrics.runtimeEquity;
        risk.metricValue = metrics.runtimeEquity;
        risk.thresholdValue = 0;
        risk.comparison = ComparisonKind.Gte;
        risk.metadata = abi.encode(metrics.runtimePnl, metrics.markMarginRatio, metrics.maintenanceThreshold);
    }

    function _readPrice(PhEvm.ForkId memory fork) internal view returns (uint256 price) {
        return _suiteReadUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.getPrice, ()), fork);
    }

    function _readCollateral(address account, PhEvm.ForkId memory fork) internal view returns (uint256 collateral) {
        return _suiteReadUintAt(VAULT, abi.encodeCall(IDenariaVaultLike.userCollateral, (account)), fork);
    }

    function _readSignedInsuranceFund(PhEvm.ForkId memory fork) internal view returns (int256 signedInsuranceFund) {
        uint256 amount = _suiteReadUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.insuranceFund, ()), fork);
        bool sign = _suiteReadBoolAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.insuranceFundSign, ()), fork);
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

/// @title DenariaOperationSafetyAssertion
/// @author Phylax Systems
/// @notice Example single-entry assertion bundle for Denaria.
/// @dev Usage:
///      `cl.assertion({ adopter: denariaPerpPair, createData: abi.encodePacked(type(DenariaOperationSafetyAssertion).creationCode, abi.encode(denariaPerpPair, denariaVault)), fnSelector: DenariaOperationSafetyAssertion.assertOperationSafety.selector })`
///      `cl.assertion({ adopter: denariaVault, createData: abi.encodePacked(type(DenariaOperationSafetyAssertion).creationCode, abi.encode(denariaPerpPair, denariaVault)), fnSelector: DenariaOperationSafetyAssertion.assertOperationSafety.selector })`
///
///      Register it once against `PerpPair` and once against `Vault` to cover Denaria's trade,
///      liquidity, PnL realization, liquidation, and collateral-removal paths with one bundle.
contract DenariaOperationSafetyAssertion is PerpetualBaseAssertion {
    IPerpetualProtectionSuite internal immutable SUITE;

    constructor(address perpPair_, address vault_) {
        SUITE = IPerpetualProtectionSuite(address(new DenariaProtectionSuite(perpPair_, vault_)));
    }

    function _suite() internal view override returns (IPerpetualProtectionSuite) {
        return SUITE;
    }
}

/// @title DenariaPostMutationRiskAssertion
/// @author Phylax Systems
/// @notice Compatibility alias for users who only care about the post-mutation risk gate.
contract DenariaPostMutationRiskAssertion is DenariaOperationSafetyAssertion {
    constructor(address perpPair_, address vault_) DenariaOperationSafetyAssertion(perpPair_, vault_) {}
}
