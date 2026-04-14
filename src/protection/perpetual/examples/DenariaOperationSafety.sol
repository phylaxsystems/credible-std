// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {IPerpetualProtectionSuite} from "../IPerpetualProtectionSuite.sol";
import {PerpetualBaseAssertion} from "../PerpetualBaseAssertion.sol";
import {DenariaHelpers} from "./DenariaHelpers.sol";
import {IDenariaPerpPairLike, IDenariaVaultLike} from "./DenariaInterfaces.sol";

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
contract DenariaProtectionSuite is DenariaHelpers {
    bytes32 internal constant MARGIN_RATIO_METRIC = "MARGIN_RATIO";
    bytes32 internal constant EQUITY_METRIC = "EQUITY";
    bytes32 internal constant LP_LEVERAGE_CAPACITY_METRIC = "LP_LEVERAGE_CAPACITY";
    bytes32 internal constant TAKER_WORSE_THAN_MARK = "TAKER_WORSE_THAN_MARK";
    bytes32 internal constant TRADE_LIQUIDITY_COVERAGE = "TRADE_LIQUIDITY_COVERAGE";
    bytes32 internal constant LIQUIDATION_GATED_BY_MMR = "LIQUIDATION_GATED_BY_MMR";
    bytes32 internal constant RISK_MARK_ANCHORED = "RISK_MARK_ANCHORED";
    bytes32 internal constant EQUITY_CONSERVATION = "EQUITY_CONSERVATION";
    bytes32 internal constant LP_EXIT_DUST = "LP_EXIT_DUST";
    bytes32 internal constant LP_BALANCE_OVERFLOW = "LP_BALANCE_OVERFLOW";

    /// @notice Maximum allowed rounding tolerance for accounting conservation checks (1e15 wei = 0.001 token).
    uint256 internal constant ACCOUNTING_EPSILON = 1e15;

    constructor(address perpPair_, address vault_) DenariaHelpers(perpPair_, vault_) {}

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
            _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.globalLiquidityStable, ()), beforeFork);
        uint256 currentAssetLiquidity =
            _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.globalLiquidityAsset, ()), beforeFork);

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

    /// @notice Builds accounting-conservation checks for Denaria settlement paths.
    /// @dev Solvency-only checks (`_buildNoBadDebtRiskState`) are insufficient for Denaria because
    ///      stale LP share math in `getLpLiquidityBalance` / `calcPnL` can credit an account with
    ///      more value than it should receive during `removeLiquidity` or `closeAndWithdraw`. The
    ///      account never goes negative, so it passes the equity >= 0 gate, but it extracts
    ///      unjustified economic value from the pool.
    ///
    ///      Three checks are applied:
    ///
    ///      - EQUITY_CONSERVATION: runtime equity must not increase beyond rounding tolerance
    ///        across the triggered call. Catches intra-call accounting drift (e.g. a
    ///        removeLiquidity whose internal trade inflates equity in the same frame).
    ///
    ///      - LP_EXIT_DUST: after a full LP exit, residual LP balances and debts must be zero
    ///        (within epsilon). Catches incomplete position teardown.
    ///
    ///      - LP_BALANCE_OVERFLOW: an LP's balance must be strictly below the pool total.
    ///        Catches the March 2026 exploit where matrix rounding produces a negative int256,
    ///        the bare uint256() cast wraps it to near-max, and the cap at globalLiquidity
    ///        gives the attacker credit for the entire pool. Because the inflation happens
    ///        during a prior trade (different account), the equity delta across realizePnL
    ///        is near-zero — only this direct balance-vs-pool check detects the overflow.
    function getAccountingConservationChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view override returns (AccountingConservationCheck[] memory checks) {
        triggered;

        if (
            operation.kind != OperationKind.RemoveLiquidity && operation.kind != OperationKind.DecreasePosition
                && operation.kind != OperationKind.RealizePnL
        ) {
            return new AccountingConservationCheck[](0);
        }

        DenariaAccountMetrics memory beforeMetrics = _readAccountMetrics(operation.account, beforeFork);
        DenariaAccountMetrics memory afterMetrics = _readAccountMetrics(operation.account, afterFork);

        int256 equityDelta = afterMetrics.runtimeEquity - beforeMetrics.runtimeEquity;

        bool fullLpExit = (beforeMetrics.lpStableBalance + beforeMetrics.lpAssetBalance > 0)
            && (afterMetrics.lpStableBalance + afterMetrics.lpAssetBalance == 0);

        (bool lpOverflow, AccountingConservationCheck memory overflowCheck) =
            _buildLpOverflowCheck(beforeMetrics, operation.account, beforeFork);

        uint256 checkCount = 1;
        if (fullLpExit) ++checkCount;
        if (lpOverflow) ++checkCount;

        checks = new AccountingConservationCheck[](checkCount);

        // Primary check: equity must not increase beyond rounding tolerance.
        checks[0] = AccountingConservationCheck({
            checkName: EQUITY_CONSERVATION,
            account: operation.account,
            market: PERP_PAIR,
            actualDelta: equityDelta,
            minAllowedDelta: type(int256).min,
            maxAllowedDelta: _toInt256(ACCOUNTING_EPSILON),
            metadata: abi.encode(
                operation.kind,
                beforeMetrics.runtimeEquity,
                afterMetrics.runtimeEquity,
                beforeMetrics.collateral,
                afterMetrics.collateral,
                beforeMetrics.runtimePnl,
                afterMetrics.runtimePnl
            )
        });

        uint256 nextIdx = 1;

        // Secondary check: after a full LP exit, no residual LP balances should remain.
        if (fullLpExit) {
            int256 residualLp = _toInt256(
                afterMetrics.lpStableBalance + afterMetrics.lpAssetBalance + afterMetrics.lpDebtStable
                    + afterMetrics.lpDebtAsset
            );
            checks[nextIdx] = AccountingConservationCheck({
                checkName: LP_EXIT_DUST,
                account: operation.account,
                market: PERP_PAIR,
                actualDelta: residualLp,
                minAllowedDelta: 0,
                maxAllowedDelta: _toInt256(ACCOUNTING_EPSILON),
                metadata: abi.encode(
                    afterMetrics.lpStableBalance,
                    afterMetrics.lpAssetBalance,
                    afterMetrics.lpDebtStable,
                    afterMetrics.lpDebtAsset
                )
            });
            ++nextIdx;
        }

        // Overflow cap check (delegated to _buildLpOverflowCheck).
        if (lpOverflow) {
            checks[nextIdx] = overflowCheck;
        }
    }

    /// @notice Detects the LP balance overflow cap — the fingerprint of the Denaria exploit.
    /// @dev When getLpLiquidityBalance computes a negative int256 (due to matrix rounding),
    ///      the bare uint256() cast wraps it to near-max. The subsequent cap at
    ///      globalLiquidityAsset/Stable gives the attacker credit for the entire pool.
    ///      This helper returns true when an LP's balance equals the pool total on either side.
    function _buildLpOverflowCheck(
        DenariaAccountMetrics memory beforeMetrics,
        address account,
        PhEvm.ForkId memory beforeFork
    ) internal view returns (bool found, AccountingConservationCheck memory check) {
        if (beforeMetrics.lpAssetBalance == 0 && beforeMetrics.lpStableBalance == 0) {
            return (false, check);
        }

        uint256 globalLiqAsset =
            _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.globalLiquidityAsset, ()), beforeFork);
        uint256 globalLiqStable =
            _readUintAt(PERP_PAIR, abi.encodeCall(IDenariaPerpPairLike.globalLiquidityStable, ()), beforeFork);

        bool assetAtCap = beforeMetrics.lpAssetBalance == globalLiqAsset && globalLiqAsset > 0;
        bool stableAtCap = beforeMetrics.lpStableBalance == globalLiqStable && globalLiqStable > 0;

        if (!assetAtCap && !stableAtCap) {
            return (false, check);
        }

        // actualDelta = lpBalance - globalLiquidity = 0 when at cap.
        // Allowed range [type(int256).min, -1] requires strictly negative (below cap).
        int256 overflowDelta = assetAtCap
            ? _toInt256(beforeMetrics.lpAssetBalance) - _toInt256(globalLiqAsset)
            : _toInt256(beforeMetrics.lpStableBalance) - _toInt256(globalLiqStable);

        check = AccountingConservationCheck({
            checkName: LP_BALANCE_OVERFLOW,
            account: account,
            market: PERP_PAIR,
            actualDelta: overflowDelta,
            minAllowedDelta: type(int256).min,
            maxAllowedDelta: -1,
            metadata: abi.encode(
                assetAtCap,
                beforeMetrics.lpAssetBalance,
                globalLiqAsset,
                stableAtCap,
                beforeMetrics.lpStableBalance,
                globalLiqStable
            )
        });

        return (true, check);
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

        risk.isHealthy = metrics.runtimeEquity >= 0 && withdrawMarkMarginRatio >= metrics.maintenanceThreshold
            && metrics.lpLeverageHealthy;
        risk.hasBadDebt = metrics.runtimeEquity < 0;
        risk.isLiquidatable = metrics.openNotional != 0 && withdrawMarkMarginRatio <= metrics.maintenanceThreshold;
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
