// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";

/// @title ILendingProtectionSuite
/// @author Phylax Systems
/// @notice Step-oriented interface for protocol-specific lending protection suites.
/// @dev Implementations expose the protocol-specific plumbing needed to assert a shared family of
///      lending-protocol invariants:
///      - any successful action that increases debt or reduces effective collateral must leave the
///        affected account solvent under the protocol's own risk metric
///      - successful withdrawals must not consume more claim than the account had before the call
///      - successful liquidations must not consume more debt or collateral than existed before the call
///      The bounded-consumption portion should be measured from the successful call's actual effect,
///      such as traced return data, ERC20 transfer deltas, or protocol-emitted events, rather than
///      from the requested input amount alone.
///
///      Expected assertion flow:
///      1. Read monitored selectors from `getMonitoredSelectors()`.
///      2. Resolve the caller-aware `TriggeredCall`.
///      3. Decode the triggered call with `decodeOperation(...)`.
///      4. Read operation-specific consumption checks with `getConsumptionChecks(...)` and require
///         `consumed <= availableBefore` for each returned check.
///      5. Filter to solvency-relevant operations with `shouldCheckPostOperationSolvency(...)`.
///      6. Read the account snapshot with `getAccountSnapshot(...)`.
///      7. Require `snapshot.solvency.isSolvent == true`.
///
///      Different protocols can encode different solvency metrics while preserving the same invariant:
///      - Aave-like systems can expose `metric = healthFactor`, `threshold = 1e18`, `comparison = Gte`.
///      - Euler-like systems can expose `metric = collateralValue - liabilityValue`,
///        `threshold = 0`, `comparison = Gt`.
interface ILendingProtectionSuite {
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

    /// @notice The lending action being inspected for shared post-operation safety checks.
    enum OperationKind {
        Unknown,
        Borrow,
        WithdrawCollateral,
        DisableCollateral,
        TransferCollateral,
        Liquidation
    }

    /// @notice Comparison rule for the protocol-defined solvency metric.
    enum ComparisonKind {
        Unknown,
        Gte,
        Gt
    }

    /// @notice Protocol-decoded context for a monitored lending call.
    struct OperationContext {
        /// @notice The adopter selector that produced this operation context.
        bytes4 selector;
        /// @notice The high-level action kind.
        OperationKind kind;
        /// @notice The immediate caller of the adopter frame.
        address caller;
        /// @notice The primary account whose solvency should be checked after the operation.
        address account;
        /// @notice The primary asset involved in the action, if any.
        address asset;
        /// @notice Optional second asset involved in the action, if any.
        /// @dev This is primarily useful for multi-asset operations such as liquidation, where
        ///      `asset` can represent the debt asset and `relatedAsset` the collateral asset.
        address relatedAsset;
        /// @notice Secondary account involved in the action, if any (receiver, liquidator, etc.).
        address counterparty;
        /// @notice Protocol-decoded requested or declared amount associated with the action, if any.
        /// @dev For clipped operations, this may differ from the actual amount later enforced by
        ///      `getConsumptionChecks(...)`.
        uint256 amount;
        /// @notice True when the action increases the account's debt exposure.
        bool increasesDebt;
        /// @notice True when the action reduces the account's effective collateral.
        bool reducesEffectiveCollateral;
        /// @notice Extension point for protocol-specific metadata.
        bytes metadata;
    }

    /// @notice Protocol-normalized aggregate state for an account at a snapshot fork.
    struct AccountState {
        /// @notice The account whose state was read.
        address account;
        /// @notice Aggregate collateral value using the implementation's protocol-defined accounting units.
        uint256 totalCollateralValue;
        /// @notice Aggregate debt value using the implementation's protocol-defined accounting units.
        uint256 totalDebtValue;
        /// @notice Whether the account currently has any open debt.
        bool hasDebt;
        /// @notice Extension point for protocol-specific aggregate data.
        bytes metadata;
    }

    /// @notice Per-asset balance and value data for an account at a snapshot fork.
    struct AccountBalance {
        /// @notice The reserve, market, or asset address represented by this balance entry.
        address asset;
        /// @notice Raw collateral or supplied balance tracked for the account.
        uint256 collateralBalance;
        /// @notice Raw debt balance tracked for the account.
        uint256 debtBalance;
        /// @notice Protocol-normalized collateral value for this asset.
        uint256 collateralValue;
        /// @notice Protocol-normalized debt value for this asset.
        uint256 debtValue;
        /// @notice Whether this asset currently counts as collateral for the account.
        bool countsAsCollateral;
        /// @notice Extension point for protocol-specific per-asset metadata.
        bytes metadata;
    }

    /// @notice Protocol-defined solvency output for an account at a snapshot fork.
    struct SolvencyState {
        /// @notice Whether the account is solvent under the protocol's own rules.
        bool isSolvent;
        /// @notice Whether the protocol would consider the account liquidatable at this snapshot.
        bool isLiquidatable;
        /// @notice Identifier for the solvency metric, e.g. "HEALTH_FACTOR" or "LIQUIDITY_EXCESS".
        bytes32 metricName;
        /// @notice Protocol-normalized solvency metric.
        int256 metric;
        /// @notice Threshold that the metric is compared against.
        int256 threshold;
        /// @notice Comparison rule used to interpret `metric` vs `threshold`.
        ComparisonKind comparison;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice Full post-operation snapshot for a monitored account.
    struct AccountSnapshot {
        /// @notice Aggregate state for the monitored account.
        AccountState state;
        /// @notice Per-asset balances. Implementations may return an empty array on the hot path.
        AccountBalance[] balances;
        /// @notice Protocol-defined solvency decision for the snapshot.
        SolvencyState solvency;
    }

    /// @notice One concrete resource-consumption bound that must hold for a successful operation.
    struct ConsumptionCheck {
        /// @notice Identifier for the bound being asserted, e.g. "WITHDRAW_CLAIM".
        bytes32 checkName;
        /// @notice The account whose pre-operation resource balance caps the consumption.
        address account;
        /// @notice The asset whose pre-operation balance or claim is being bounded.
        address asset;
        /// @notice Resource available before the operation in protocol-defined accounting units.
        uint256 availableBefore;
        /// @notice Actual resource consumed by the successful operation in the same units.
        uint256 consumed;
        /// @notice Extension point for protocol-specific evidence or decoded fields.
        bytes metadata;
    }

    /// @notice Returns the adopter selectors that can participate in the shared lending invariants.
    /// @dev Implementations should return the selectors that the generic assertion must subscribe to on
    ///      the adopter. These selectors do not all need to be solvency-worsening on every invocation;
    ///      `decodeOperation(...)` and `shouldCheckPostOperationSolvency(...)` can later discard benign
    ///      or no-op cases. The returned list is typically protocol-entrypoint specific.
    /// @return selectors Selectors that should trigger the generic lending operation-safety assertion.
    function getMonitoredSelectors() external view returns (bytes4[] memory selectors);

    /// @notice Decodes the triggered adopter call into a protocol-normalized operation context.
    /// @dev Caller-aware decoding is necessary because some protocols encode the affected account in
    ///      `msg.sender` instead of calldata. Implementations should populate `operation.account`
    ///      with the account whose post-operation solvency must be checked and mark whether the call
    ///      increased debt and/or reduced effective collateral. Unsupported or irrelevant selectors
    ///      should normally return the zero-value `OperationContext` rather than revert.
    /// @param triggered The exact adopter frame that caused the assertion to run.
    /// @return operation Protocol-normalized context used by downstream filtering and checks.
    function decodeOperation(TriggeredCall calldata triggered) external view returns (OperationContext memory operation);

    /// @notice Returns whether the decoded action must preserve post-operation solvency.
    /// @dev This is the last protocol-specific filter before snapshot reads happen. Implementations
    ///      should return `false` for actions that are not risk-increasing in the shared sense,
    ///      such as enabling collateral, zero-amount paths, or protocol no-ops.
    /// @param operation The decoded operation context returned by `decodeOperation(...)`.
    /// @return shouldCheck True when the assertion should read state and enforce solvency.
    function shouldCheckPostOperationSolvency(OperationContext calldata operation)
        external
        view
        returns (bool shouldCheck);

    /// @notice Returns the bounded-consumption checks implied by the decoded operation.
    /// @dev Each returned entry is enforced as `consumed <= availableBefore`. Implementations should
    ///      return an empty array when the operation has no shared bounded-consumption invariant.
    ///      `consumed` must reflect the actual effect of the successful call, not merely the
    ///      requested amount. This lets suites support clipped operations such as partial withdraws
    ///      or capped liquidations without bespoke assertion logic in the base contract. Suitable
    ///      data sources include traced call output, ERC20 transfer introspection, or decoded logs.
    /// @param triggered The exact adopter frame that caused the assertion to run.
    /// @param operation The decoded operation context returned by `decodeOperation(...)`.
    /// @param beforeFork The pre-call snapshot fork.
    /// @param afterFork The post-call snapshot fork.
    /// @return checks Operation-specific bounds to enforce for the successful call.
    function getConsumptionChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view returns (ConsumptionCheck[] memory checks);

    /// @notice Reads the account snapshot used by the post-operation solvency assertion.
    /// @dev Implementations can override this with a protocol-optimized hot path instead of forcing
    ///      the assertion to always compute per-asset balances. The returned snapshot must describe
    ///      the post-operation state at `fork`. The shared suite default in
    ///      `LendingBaseAssertion.sol` composes this from `getAccountState(...)`,
    ///      `getAccountBalances(...)`, and `evaluateSolvency(...)`.
    /// @param account The account whose post-operation solvency is being checked.
    /// @param fork The post-call snapshot fork that should be queried.
    /// @return snapshot Aggregate state, optional per-asset balances, and the final solvency result.
    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        returns (AccountSnapshot memory snapshot);

    /// @notice Reads protocol-normalized aggregate account state at a given snapshot fork.
    /// @dev Implementations should return enough aggregate information for downstream solvency logic
    ///      and debugging. Protocol-specific fields that do not fit the common shape belong in
    ///      `state.metadata`.
    /// @param account The account whose risk state should be inspected.
    /// @param fork The snapshot fork to read from.
    /// @return state Aggregate account state in protocol-defined accounting units.
    function getAccountState(address account, PhEvm.ForkId calldata fork)
        external
        view
        returns (AccountState memory state);

    /// @notice Reads protocol-normalized per-asset balances for an account at a snapshot fork.
    /// @dev Implementations may return an empty array when balances are not required for the
    ///      hot-path solvency decision and `getAccountSnapshot(...)` already exposes an optimized path.
    ///      When provided, balances should use the same valuation units as `AccountState`.
    /// @param account The account whose positions should be inspected.
    /// @param fork The snapshot fork to read from.
    /// @return balances Per-asset collateral and debt entries relevant to the account.
    function getAccountBalances(address account, PhEvm.ForkId calldata fork)
        external
        view
        returns (AccountBalance[] memory balances);

    /// @notice Evaluates the protocol's solvency rule from the decoded account snapshot.
    /// @dev Implementations should encode the exact rule the protocol uses to decide whether an
    ///      account is solvent or liquidatable. `state` and `balances` are passed separately so
    ///      simple protocols can decide from aggregate state alone while more complex protocols can
    ///      inspect per-asset positions.
    /// @param state Aggregate account state returned by `getAccountState(...)`.
    /// @param balances Per-asset balances returned by `getAccountBalances(...)`.
    /// @param fork The snapshot fork used for the solvency evaluation.
    /// @return solvency Protocol-defined solvency decision and supporting metric data.
    function evaluateSolvency(
        AccountState calldata state,
        AccountBalance[] calldata balances,
        PhEvm.ForkId calldata fork
    ) external view returns (SolvencyState memory solvency);
}
