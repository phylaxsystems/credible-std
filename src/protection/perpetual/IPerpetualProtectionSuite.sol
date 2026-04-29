// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";

/// @title IPerpetualProtectionSuite
/// @author Phylax Systems
/// @notice Step-oriented interface for protocol-specific perpetual protection adapters.
/// @dev Implementations expose the protocol-specific plumbing needed to assert a shared family of
///      perpetual-protocol invariants:
///      - any non-liquidation user mutation must not create self-bad-debt and must leave the
///        affected account healthy under the protocol's own mark-to-market risk rule
///      - taker execution must stay at or worse than the protocol's externally anchored mark
///      - open exposure must remain backed by explicit liquidity or liability accounting
///      - funding settlement must be derived from cumulative-state deltas rather than ad hoc values
///      - liquidation is the only path that may realize deficit, and it must be gated by pre-state
///        unhealthiness while routing any realized loss into an explicit absorber
///      - risk-critical transitions must stay anchored to an external oracle or equivalent mark
///
///      Expected assertion flow:
///      1. Read monitored selectors from `getMonitoredSelectors()`.
///      2. Resolve the caller-aware `TriggeredCall`.
///      3. Decode the triggered call with `decodeOperation(...)`.
///      4. Read and enforce any suite-provided execution, liquidity, funding, liquidation, and
///         oracle-anchor checks for the successful call.
///      5. Filter to non-liquidation risk-preserving operations with
///         `shouldCheckPostMutationRisk(...)`.
///      6. Read the post-mutation snapshot with `getPostMutationSnapshot(...)`.
///      7. Require `snapshot.risk.equity >= 0`, `snapshot.risk.hasBadDebt == false`, and
///         `snapshot.risk.isHealthy == true`.
interface IPerpetualProtectionSuite {
    /// @notice Resolved information about the exact adopter call that triggered the assertion.
    struct TriggeredCall {
        /// @notice Function selector invoked on the adopter.
        bytes4 selector;
        /// @notice Immediate caller of the adopter frame.
        address caller;
        /// @notice Adopter target address that was called.
        address target;
        /// @notice Raw calldata for the adopter frame.
        bytes input;
        /// @notice Call identifier used to construct a PreCall snapshot.
        uint256 callStart;
        /// @notice Call identifier used to construct a PostCall snapshot.
        uint256 callEnd;
    }

    /// @notice The perpetual action being inspected for shared post-operation safety checks.
    enum OperationKind {
        Unknown,
        IncreasePosition,
        DecreasePosition,
        DepositCollateral,
        WithdrawCollateral,
        AddLiquidity,
        RemoveLiquidity,
        SettleFunding,
        RealizePnL,
        Liquidation
    }

    /// @notice Comparison rule for the protocol-defined post-mutation risk metric.
    enum ComparisonKind {
        Unknown,
        Gte,
        Gt
    }

    /// @notice Protocol-decoded context for a monitored perpetual call.
    struct OperationContext {
        /// @notice The adopter selector that produced this operation context.
        bytes4 selector;
        /// @notice The high-level action kind.
        OperationKind kind;
        /// @notice The immediate caller of the adopter frame.
        address caller;
        /// @notice The primary account whose risk state should be checked after the operation.
        address account;
        /// @notice The market, product, or pair being mutated, if any.
        address market;
        /// @notice Primary collateral or settlement asset involved in the action, if any.
        address collateralAsset;
        /// @notice Secondary account involved in the action, if any.
        address counterparty;
        /// @notice Position direction when the operation is market-directional.
        bool isLong;
        /// @notice Absolute exposure delta requested or realized by the action.
        uint256 sizeDelta;
        /// @notice Signed collateral delta in protocol-defined units, when known.
        int256 collateralDelta;
        /// @notice User-specified price bound or execution hint, if any.
        uint256 limitPrice;
        /// @notice True when the action mutates open exposure.
        bool mutatesExposure;
        /// @notice True when the action can reduce the account's post-state safety margin.
        bool reducesAccountSafety;
        /// @notice True when the action is a liquidation or other exceptional bad-debt path.
        bool isLiquidation;
        /// @notice Extension point for protocol-specific metadata.
        bytes metadata;
    }

    /// @notice Protocol-normalized aggregate mark-to-market state for an account.
    struct AccountState {
        /// @notice The account whose state was read.
        address account;
        /// @notice Total collateral or margin value in protocol-defined accounting units.
        uint256 collateralValue;
        /// @notice Total open notional or equivalent exposure measure.
        uint256 openNotional;
        /// @notice Aggregate unrealized PnL at the protocol's mark price.
        int256 unrealizedPnl;
        /// @notice Aggregate unsettled or accrued funding at the protocol's mark state.
        int256 accruedFunding;
        /// @notice Whether the account currently has any open exposure.
        bool hasOpenExposure;
        /// @notice Extension point for protocol-specific aggregate data.
        bytes metadata;
    }

    /// @notice Protocol-normalized per-market position data for an account.
    struct PositionState {
        /// @notice The market, product, or pair represented by this entry.
        address market;
        /// @notice Collateral or settlement asset associated with the position.
        address collateralAsset;
        /// @notice Direction of the position when applicable.
        bool isLong;
        /// @notice Position size in protocol-defined units.
        uint256 size;
        /// @notice Position notional in protocol-defined units.
        uint256 openNotional;
        /// @notice Position-level collateral or margin allocation.
        uint256 collateralValue;
        /// @notice Position PnL at the protocol's mark price.
        int256 pnl;
        /// @notice Position-level accrued funding at the snapshot.
        int256 accruedFunding;
        /// @notice Position mark price used by the protocol's risk engine.
        uint256 markPrice;
        /// @notice Position maintenance requirement in protocol-defined units.
        uint256 maintenanceRequirement;
        /// @notice Extension point for protocol-specific per-position metadata.
        bytes metadata;
    }

    /// @notice Protocol-defined post-operation risk output for an account at a snapshot fork.
    struct RiskState {
        /// @notice Whether the account is healthy under the protocol's own post-state rules.
        bool isHealthy;
        /// @notice Whether the account has entered a self-bad-debt state.
        bool hasBadDebt;
        /// @notice Whether the protocol would consider the account liquidatable at this snapshot.
        bool isLiquidatable;
        /// @notice Identifier for the protocol's primary risk metric, e.g. "MARGIN_RATIO".
        bytes32 metricName;
        /// @notice Mark-to-market account equity after collateral, PnL, and funding.
        int256 equity;
        /// @notice Protocol-normalized post-state safety metric or equivalent.
        int256 metricValue;
        /// @notice Threshold compared against `metricValue`.
        int256 thresholdValue;
        /// @notice Comparison rule used to interpret `metricValue` vs `thresholdValue`.
        ComparisonKind comparison;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice Full post-operation snapshot for a monitored account.
    struct AccountSnapshot {
        /// @notice Aggregate state for the monitored account.
        AccountState state;
        /// @notice Per-market positions. Implementations may return an empty array on the hot path.
        PositionState[] positions;
        /// @notice Protocol-defined post-operation risk decision.
        RiskState risk;
    }

    /// @notice One concrete taker-price bound that must hold for a successful operation.
    struct ExecutionPriceCheck {
        /// @notice Identifier for the bound being asserted, e.g. "TAKER_WORSE_THAN_MARK".
        bytes32 checkName;
        /// @notice The account whose trade is being bounded.
        address account;
        /// @notice The market whose execution is being inspected.
        address market;
        /// @notice Actual execution price in protocol-defined price units.
        uint256 executionPrice;
        /// @notice Inclusive lower bound on the allowed execution price.
        uint256 minExecutionPrice;
        /// @notice Inclusive upper bound on the allowed execution price.
        uint256 maxExecutionPrice;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice One concrete liquidity or liability coverage bound that must hold after a mutation.
    struct LiquidityCoverageCheck {
        /// @notice Identifier for the bound being asserted, e.g. "RESERVE_COVERAGE".
        bytes32 checkName;
        /// @notice The market whose liquidity bucket is being checked.
        address market;
        /// @notice The pool, vault, insurance fund, or liability bucket used as the source of coverage.
        address accountingBucket;
        /// @notice Required amount implied by the post-state exposure or liability.
        uint256 requiredAmount;
        /// @notice Available amount in the backing bucket.
        uint256 availableAmount;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice One concrete funding-settlement check derived from cumulative funding state.
    struct FundingDeltaCheck {
        /// @notice Identifier for the bound being asserted, e.g. "FUNDING_SETTLEMENT".
        bytes32 checkName;
        /// @notice The account whose funding is being inspected.
        address account;
        /// @notice The market whose funding state is being inspected.
        address market;
        /// @notice Actual funding charged or credited by the successful operation.
        int256 actualFunding;
        /// @notice Inclusive lower bound implied by cumulative funding deltas.
        int256 minExpectedFunding;
        /// @notice Inclusive upper bound implied by cumulative funding deltas.
        int256 maxExpectedFunding;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice One concrete liquidation-path check for exceptional bad-debt handling.
    struct LiquidationCheck {
        /// @notice Identifier for the bound being asserted, e.g. "ONLY_UNHEALTHY_LIQUIDATABLE".
        bytes32 checkName;
        /// @notice The account being liquidated.
        address account;
        /// @notice The market whose liquidation path is being inspected.
        address market;
        /// @notice Whether the account was unsafe before the liquidation executed.
        bool wasLiquidatableBefore;
        /// @notice Positive realized deficit that the liquidation created, if any.
        int256 lossCreated;
        /// @notice Amount explicitly absorbed by the loss-bearing account or bucket.
        uint256 absorbedLoss;
        /// @notice Loss-bearing account or bucket, if any.
        address absorber;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice One concrete accounting-conservation bound for a non-liquidation settlement path.
    /// @dev Catches exploit families where an operation creates unjustified economic gain through
    ///      stale LP share math, double-counted PnL, or accounting drift — scenarios that pass a
    ///      solvency-only check because the account never goes negative.
    struct AccountingConservationCheck {
        /// @notice Identifier for the bound being asserted, e.g. "EQUITY_CONSERVATION".
        bytes32 checkName;
        /// @notice The account whose accounting is being inspected.
        address account;
        /// @notice The market whose accounting path is being inspected.
        address market;
        /// @notice Actual economic delta observed across the operation (e.g. post-equity minus pre-equity).
        int256 actualDelta;
        /// @notice Inclusive lower bound on the allowed economic delta.
        int256 minAllowedDelta;
        /// @notice Inclusive upper bound on the allowed economic delta.
        int256 maxAllowedDelta;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice One concrete oracle-anchor bound for a risk-critical transition.
    struct OracleAnchorCheck {
        /// @notice Identifier for the bound being asserted, e.g. "RISK_MARK_ANCHORED".
        bytes32 checkName;
        /// @notice The market whose oracle anchoring is being inspected.
        address market;
        /// @notice Actual price used by the protocol for the checked path.
        uint256 usedPrice;
        /// @notice Inclusive lower bound implied by the external oracle or mark source.
        uint256 minOraclePrice;
        /// @notice Inclusive upper bound implied by the external oracle or mark source.
        uint256 maxOraclePrice;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice Returns the adopter selectors that can participate in the shared perpetual invariants.
    /// @return selectors Selectors that should trigger the generic perpetual operation-safety assertion.
    function getMonitoredSelectors() external view returns (bytes4[] memory selectors);

    /// @notice Decodes the triggered adopter call into a protocol-normalized operation context.
    /// @param triggered The exact adopter frame that caused the assertion to run.
    /// @return operation Protocol-normalized context used by downstream filtering and checks.
    function decodeOperation(TriggeredCall calldata triggered) external view returns (OperationContext memory operation);

    /// @notice Returns whether the decoded action must preserve post-mutation health.
    /// @dev This should normally be true for non-liquidation user actions that can reduce effective
    ///      account safety, such as increasing leverage, withdrawing collateral, realizing losses,
    ///      or removing LP capital against an LP leverage bound.
    /// @param operation The decoded operation context returned by `decodeOperation(...)`.
    /// @return shouldCheck True when the assertion should read state and enforce the post-state risk rule.
    function shouldCheckPostMutationRisk(OperationContext calldata operation) external view returns (bool shouldCheck);

    /// @notice Returns suite-provided execution-price bounds for the decoded operation.
    function getExecutionPriceChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (ExecutionPriceCheck[] memory checks);

    /// @notice Returns suite-provided liquidity or liability coverage bounds for the decoded operation.
    function getLiquidityCoverageChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (LiquidityCoverageCheck[] memory checks);

    /// @notice Returns suite-provided cumulative-funding settlement bounds for the decoded operation.
    function getFundingDeltaChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (FundingDeltaCheck[] memory checks);

    /// @notice Returns suite-provided liquidation-path bounds for the decoded operation.
    function getLiquidationChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (LiquidationCheck[] memory checks);

    /// @notice Returns suite-provided oracle-anchor bounds for the decoded operation.
    function getOracleAnchorChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (OracleAnchorCheck[] memory checks);

    /// @notice Returns suite-provided accounting-conservation bounds for the decoded operation.
    /// @dev These checks catch exploit families where a non-liquidation settlement or
    ///      liquidity-removal path creates unjustified economic gain through LP accounting
    ///      drift, stale share math, or double-counted PnL.
    function getAccountingConservationChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (AccountingConservationCheck[] memory checks);

    /// @notice Reads the operation-aware snapshot used by the post-mutation risk assertion.
    /// @dev Implementations may return the same result as `getAccountSnapshot(...)` when their
    ///      post-state rule depends only on the account and fork. Protocols with action-specific
    ///      postconditions may override this to select the appropriate metric for the decoded
    ///      operation.
    function getPostMutationSnapshot(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata fork
    ) external view returns (AccountSnapshot memory snapshot);

    /// @notice Reads the account snapshot used by the post-mutation risk assertion.
    /// @param account The account whose post-operation risk state is being checked.
    /// @param fork The post-call snapshot fork that should be queried.
    /// @return snapshot Aggregate state, optional per-market positions, and the final risk result.
    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        returns (AccountSnapshot memory snapshot);

    /// @notice Reads protocol-normalized aggregate account state at a given snapshot fork.
    function getAccountState(address account, PhEvm.ForkId calldata fork)
        external
        view
        returns (AccountState memory state);

    /// @notice Reads protocol-normalized per-market positions for an account at a snapshot fork.
    function getAccountPositions(address account, PhEvm.ForkId calldata fork)
        external
        view
        returns (PositionState[] memory positions);

    /// @notice Evaluates the protocol's post-state risk rule from the decoded account snapshot.
    function evaluateRisk(AccountState calldata state, PositionState[] calldata positions, PhEvm.ForkId calldata fork)
        external
        view
        returns (RiskState memory risk);
}
