// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {ILendingProtectionSuite} from "../ILendingProtectionSuite.sol";
import {LendingBaseAssertion, LendingProtectionSuiteBase} from "../LendingBaseAssertion.sol";
import {
    AaveV3Types,
    IAaveV3AddressesProviderLike,
    IAaveV3OracleLike,
    IAaveV3PoolLike,
    IERC20MetadataLike
} from "./AaveV3Interfaces.sol";

/// @title AaveV3HorizonProtectionSuite
/// @author Phylax Systems
/// @notice Example `ILendingProtectionSuite` targeting a local Aave v3 Horizon deployment.
/// @dev This is intentionally aligned with the Aave v3 Horizon pool paths found in
///      `~/Documents/code/solidity/aave-v3-horizon/`:
///      - `borrow(...)`
///      - `withdraw(...)`
///      - `liquidationCall(...)`
///      - `setUserUseReserveAsCollateral(asset, false)`
///      - `finalizeTransfer(...)` for aToken transfers that reduce effective collateral.
contract AaveV3HorizonProtectionSuite is LendingProtectionSuiteBase {
    /// @notice Extra aggregate Aave v3 Horizon metrics kept in `AccountState.metadata`.
    /// @dev The common account shape does not have dedicated fields for these values, but they are
    ///      useful for debugging and for reconstructing the health-factor-based solvency decision.
    struct AaveAccountMetrics {
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }

    bytes32 internal constant HEALTH_FACTOR_METRIC = 0x4845414c54485f464143544f5200000000000000000000000000000000000000;
    bytes32 internal constant WITHDRAW_CLAIM_CHECK = "WITHDRAW_CLAIM";
    bytes32 internal constant LIQUIDATION_DEBT_CHECK = "LIQUIDATION_DEBT";
    bytes32 internal constant LIQUIDATION_COLLATERAL_CHECK = "LIQUIDATION_COLLATERAL";
    uint256 internal constant HEALTH_FACTOR_THRESHOLD = 1e18;
    int256 internal constant HEALTH_FACTOR_THRESHOLD_INT = 1e18;

    address internal immutable POOL;
    address internal immutable ADDRESSES_PROVIDER;

    /// @notice Creates an Aave v3 Horizon suite bound to a specific pool.
    /// @dev The assertion adopter should also be this pool, since the monitored selectors are all
    ///      pool entrypoints or pool callbacks.
    /// @param pool_ Aave v3 Horizon pool address whose accounting and selectors this suite targets.
    constructor(address pool_) {
        POOL = pool_;
        ADDRESSES_PROVIDER = IAaveV3PoolLike(pool_).ADDRESSES_PROVIDER();
    }

    /// @notice Returns the Aave v3 Horizon pool selectors relevant to the shared lending invariants.
    /// @dev These map directly to the protocol paths that Aave v3 Horizon guards with the health
    ///      factor checks or bounded-consumption checks relevant to the shared lending invariants.
    /// @return selectors Pool selectors that should trigger the generic lending operation-safety check.
    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IAaveV3PoolLike.borrow.selector;
        selectors[1] = IAaveV3PoolLike.withdraw.selector;
        selectors[2] = IAaveV3PoolLike.liquidationCall.selector;
        selectors[3] = IAaveV3PoolLike.setUserUseReserveAsCollateral.selector;
        selectors[4] = IAaveV3PoolLike.finalizeTransfer.selector;
    }

    /// @notice Decodes an Aave v3 Horizon pool call into the shared lending operation model.
    /// @dev Aave v3 Horizon mixes calldata-owned and caller-owned account semantics:
    ///      - `borrow(...)` checks the `onBehalfOf` account.
    ///      - `withdraw(...)` and `setUserUseReserveAsCollateral(...)` act on `msg.sender`.
    ///      - `liquidationCall(...)` checks the liquidated user, with `asset = debtAsset` and
    ///        `relatedAsset = collateralAsset`.
    ///      - `finalizeTransfer(...)` checks the `from` account when collateral leaves.
    ///      Calls that do not reduce risk headroom are returned as neutral operations and filtered
    ///      later by `shouldCheckPostOperationSolvency(...)`.
    /// @param triggered The exact Aave v3 Horizon pool frame that caused the assertion to run.
    /// @return operation Protocol-normalized description of the triggered action.
    function decodeOperation(TriggeredCall calldata triggered)
        external
        pure
        override
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == IAaveV3PoolLike.borrow.selector) {
            (address asset, uint256 amount,,, address onBehalfOf) =
                abi.decode(triggered.input[4:], (address, uint256, uint256, uint16, address));

            operation.kind = OperationKind.Borrow;
            operation.account = onBehalfOf;
            operation.asset = asset;
            operation.amount = amount;
            operation.increasesDebt = amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3PoolLike.withdraw.selector) {
            (address asset, uint256 amount, address to) = abi.decode(triggered.input[4:], (address, uint256, address));

            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.asset = asset;
            operation.counterparty = to;
            operation.amount = amount;
            operation.reducesEffectiveCollateral = amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3PoolLike.liquidationCall.selector) {
            (address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) =
                abi.decode(triggered.input[4:], (address, address, address, uint256, bool));

            operation.kind = OperationKind.Liquidation;
            operation.account = user;
            operation.asset = debtAsset;
            operation.relatedAsset = collateralAsset;
            operation.counterparty = triggered.caller;
            operation.amount = debtToCover;
            operation.metadata = abi.encode(receiveAToken);
            return operation;
        }

        if (triggered.selector == IAaveV3PoolLike.setUserUseReserveAsCollateral.selector) {
            (address asset, bool useAsCollateral) = abi.decode(triggered.input[4:], (address, bool));

            if (!useAsCollateral) {
                operation.kind = OperationKind.DisableCollateral;
                operation.account = triggered.caller;
                operation.asset = asset;
                operation.reducesEffectiveCollateral = true;
            }

            return operation;
        }

        if (triggered.selector == IAaveV3PoolLike.finalizeTransfer.selector) {
            (address asset, address from, address to, uint256 amount,,) =
                abi.decode(triggered.input[4:], (address, address, address, uint256, uint256, uint256));

            operation.kind = OperationKind.TransferCollateral;
            operation.account = from;
            operation.asset = asset;
            operation.counterparty = to;
            operation.amount = amount;
            operation.reducesEffectiveCollateral = from != to && amount != 0;
            return operation;
        }
    }

    /// @notice Filters decoded Aave v3 Horizon operations down to the ones that must preserve solvency.
    /// @dev This suite only checks paths that either increase debt or reduce effective collateral for
    ///      a concrete account. Neutral operations are ignored to keep the assertion cheap and avoid
    ///      false positives from selectors that are monitored broadly.
    /// @param operation The decoded operation context.
    /// @return shouldCheck True when the generic assertion should read post-call state.
    function shouldCheckPostOperationSolvency(OperationContext calldata operation)
        external
        pure
        override
        returns (bool shouldCheck)
    {
        return operation.account != address(0) && (operation.increasesDebt || operation.reducesEffectiveCollateral);
    }

    /// @notice Returns the bounded-consumption checks implied by the decoded Aave v3 Horizon operation.
    /// @dev This example exposes two shared resource bounds:
    ///      - withdraws cannot consume more aToken claim than the user had before the call
    ///      - liquidations cannot move more debt from the liquidator into the debt reserve than the
    ///        user owed before the call, and cannot move more collateral to the liquidator than the
    ///        user had before the call
    ///      Other operation kinds return an empty array.
    /// @param triggered The exact Aave v3 Horizon pool frame that caused the assertion to run.
    /// @param operation The decoded operation context.
    /// @param beforeFork The pre-call snapshot fork.
    /// @param afterFork The post-call snapshot fork.
    /// @return checks Operation-specific bounded-consumption checks for the successful call.
    function getConsumptionChecks(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) external view override returns (ConsumptionCheck[] memory checks) {
        if (operation.kind == OperationKind.WithdrawCollateral) {
            checks = new ConsumptionCheck[](1);
            checks[0] = _getWithdrawClaimCheck(triggered, operation, beforeFork);
            return checks;
        }

        if (operation.kind == OperationKind.Liquidation) {
            checks = new ConsumptionCheck[](2);
            checks[0] = _getLiquidationDebtCheck(operation, beforeFork, afterFork);
            checks[1] = _getLiquidationCollateralCheck(operation, beforeFork, afterFork);
        }
    }

    /// @notice Reads the post-call account snapshot needed by the Aave v3 Horizon solvency invariant.
    /// @dev Hot path override: the invariant itself only needs Aave's aggregate health factor, so the
    ///      suite skips per-reserve enumeration here. `getAccountBalances(...)` remains available for
    ///      richer debugging or derived assertions.
    /// @param account The account whose health factor should be checked.
    /// @param fork The post-call snapshot fork.
    /// @return snapshot Snapshot containing aggregate state and the derived health-factor decision.
    function getAccountSnapshot(address account, PhEvm.ForkId calldata fork)
        external
        view
        virtual
        override
        returns (AccountSnapshot memory snapshot)
    {
        snapshot.state = _getAccountState(account, fork);
        snapshot.solvency = _evaluateHealthFactor(snapshot.state);
    }

    /// @notice Reads Aave v3 Horizon aggregate account metrics from `Pool.getUserAccountData(...)`.
    /// @dev The returned `AccountState` uses Aave's base-currency values for total collateral and
    ///      total debt, and stores the additional health-factor inputs in `metadata`.
    /// @param account The account whose aggregate risk data should be queried.
    /// @param fork The snapshot fork to query.
    /// @return state Aggregate Aave v3 Horizon account state.
    function getAccountState(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountState memory state)
    {
        return _getAccountState(account, fork);
    }

    /// @notice Enumerates Aave v3 reserve balances for the account.
    /// @dev This is not needed on the hot path for the example invariant, but it shows how a suite
    ///      can still expose per-reserve state for debugging, richer assertions, or protocols whose
    ///      solvency rule depends on per-asset inspection.
    /// @param account The account whose reserve balances should be queried.
    /// @param fork The snapshot fork to query.
    /// @return balances One entry per non-zero reserve position.
    function getAccountBalances(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountBalance[] memory balances)
    {
        return _getAccountBalances(account, fork);
    }

    /// @notice Evaluates Aave v3 Horizon solvency from aggregate account state.
    /// @dev The example intentionally ignores per-reserve balances because Aave v3 Horizon's own post-action
    ///      checks reduce to health factor over aggregate pool data. Suites for other protocols may
    ///      need to inspect the `balances` argument instead.
    /// @param state Aggregate account state produced by `getAccountState(...)`.
    /// @param balances The per-reserve balances, unused in this implementation.
    /// @param fork The snapshot fork, unused because all required information is in `state`.
    /// @return solvency Health-factor-based solvency result.
    function evaluateSolvency(
        AccountState calldata state,
        AccountBalance[] calldata balances,
        PhEvm.ForkId calldata fork
    ) external pure override returns (SolvencyState memory solvency) {
        balances;
        fork;
        return _evaluateHealthFactor(state);
    }

    /// @notice Internal helper that reads and normalizes Aave v3 Horizon aggregate account data.
    /// @dev This is the canonical aggregate-state implementation used by both `getAccountState(...)`
    ///      and the optimized `getAccountSnapshot(...)` hot path.
    /// @param account The account whose risk data should be queried.
    /// @param fork The snapshot fork to query.
    /// @return state Aggregate state encoded in the common suite format.
    function _getAccountState(address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (AccountState memory state)
    {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3PoolLike.getUserAccountData, (account)), fork),
            (uint256, uint256, uint256, uint256, uint256, uint256)
        );

        state.account = account;
        state.totalCollateralValue = totalCollateralBase;
        state.totalDebtValue = totalDebtBase;
        state.hasDebt = totalDebtBase != 0;
        state.metadata = abi.encode(
            AaveAccountMetrics({
                availableBorrowsBase: availableBorrowsBase,
                currentLiquidationThreshold: currentLiquidationThreshold,
                ltv: ltv,
                healthFactor: healthFactor
            })
        );
    }

    /// @notice Internal helper that expands the account into reserve-level balances and values.
    /// @dev Reads the reserve list, user collateral bitset, reserve token addresses, and oracle
    ///      prices, then emits one balance entry per reserve with a non-zero collateral or debt
    ///      balance. The values are normalized to Aave's base currency.
    /// @param account The account whose reserve positions should be queried.
    /// @param fork The snapshot fork to query.
    /// @return balances One entry per non-zero reserve position.
    function _getAccountBalances(address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (AccountBalance[] memory balances)
    {
        address[] memory reserves =
            abi.decode(_viewAt(POOL, abi.encodeCall(IAaveV3PoolLike.getReservesList, ()), fork), (address[]));
        AaveV3Types.UserConfigurationMap memory userConfig = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3PoolLike.getUserConfiguration, (account)), fork),
            (AaveV3Types.UserConfigurationMap)
        );

        address oracle =
            _readAddressAt(ADDRESSES_PROVIDER, abi.encodeCall(IAaveV3AddressesProviderLike.getPriceOracle, ()), fork);

        balances = new AccountBalance[](reserves.length);
        uint256 count;

        for (uint256 i; i < reserves.length; ++i) {
            (bool include, AccountBalance memory balance) =
                _buildAccountBalance(reserves[i], account, userConfig.data, oracle, fork);

            if (!include) {
                continue;
            }

            balances[count++] = balance;
        }

        assembly {
            mstore(balances, count)
        }
    }

    /// @notice Builds the withdraw bounded-consumption check from Aave v3 Horizon call output and pre-state.
    /// @dev `Pool.withdraw(...)` returns the actual amount withdrawn, which already handles the
    ///      `type(uint256).max` full-withdraw path. The available pre-operation claim is the user's
    ///      aToken balance before the call.
    /// @param triggered The traced withdraw call.
    /// @param operation The decoded withdraw operation.
    /// @param beforeFork The pre-call snapshot fork.
    /// @return check Bound requiring actual withdrawn amount to be no greater than pre-call supply.
    function _getWithdrawClaimCheck(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork
    ) internal view returns (ConsumptionCheck memory check) {
        AaveV3Types.ReserveDataLegacy memory reserveData = _getReserveData(operation.asset, beforeFork);
        uint256 availableBefore = _readBalanceAt(reserveData.aTokenAddress, operation.account, beforeFork);
        uint256 consumed = abi.decode(ph.callOutputAt(triggered.callStart), (uint256));

        check = ConsumptionCheck({
            checkName: WITHDRAW_CLAIM_CHECK,
            account: operation.account,
            asset: operation.asset,
            availableBefore: availableBefore,
            consumed: consumed,
            metadata: abi.encode(reserveData.aTokenAddress)
        });
    }

    /// @notice Builds the liquidation debt-consumption check from actual debt-asset transfers.
    /// @dev Aave v3 Horizon clips liquidation debt to the user's actual debt or the close-factor cap.
    ///      The assertion therefore measures the actual debt asset moved from the liquidator to the
    ///      debt reserve's aToken during the successful liquidation call.
    /// @param operation The decoded liquidation operation.
    /// @param beforeFork The pre-call snapshot fork.
    /// @param afterFork The post-call snapshot fork.
    /// @return check Bound requiring repaid debt to be no greater than pre-call debt.
    function _getLiquidationDebtCheck(
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) internal view returns (ConsumptionCheck memory check) {
        AaveV3Types.ReserveDataLegacy memory reserveData = _getReserveData(operation.asset, beforeFork);
        uint256 debtBefore = _getUserReserveDebt(operation.asset, operation.account, beforeFork);
        uint256 repaidEffective =
            _transferredValueAt(operation.asset, operation.counterparty, reserveData.aTokenAddress, afterFork);

        check = ConsumptionCheck({
            checkName: LIQUIDATION_DEBT_CHECK,
            account: operation.account,
            asset: operation.asset,
            availableBefore: debtBefore,
            consumed: repaidEffective,
            metadata: abi.encode(reserveData.aTokenAddress, operation.counterparty)
        });
    }

    /// @notice Builds the liquidation collateral-consumption check from actual collateral transfers.
    /// @dev This measures what the liquidator actually receives:
    ///      - underlying collateral when `receiveAToken == false`
    ///      - collateral aTokens when `receiveAToken == true`
    ///      The bound is still capped by the user's pre-call collateral claim.
    /// @param operation The decoded liquidation operation.
    /// @param beforeFork The pre-call snapshot fork.
    /// @param afterFork The post-call snapshot fork.
    /// @return check Bound requiring seized collateral to be no greater than pre-call collateral.
    function _getLiquidationCollateralCheck(
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) internal view returns (ConsumptionCheck memory check) {
        bool receiveAToken = abi.decode(operation.metadata, (bool));
        AaveV3Types.ReserveDataLegacy memory reserveData = _getReserveData(operation.relatedAsset, beforeFork);
        uint256 collateralBefore = _readBalanceAt(reserveData.aTokenAddress, operation.account, beforeFork);
        address seizedToken = receiveAToken ? reserveData.aTokenAddress : operation.relatedAsset;
        address transferSender = receiveAToken ? operation.account : reserveData.aTokenAddress;
        uint256 seizedEffective = _transferredValueAt(seizedToken, transferSender, operation.counterparty, afterFork);

        check = ConsumptionCheck({
            checkName: LIQUIDATION_COLLATERAL_CHECK,
            account: operation.account,
            asset: operation.relatedAsset,
            availableBefore: collateralBefore,
            consumed: seizedEffective,
            metadata: abi.encode(reserveData.aTokenAddress, seizedToken, transferSender, receiveAToken)
        });
    }

    /// @notice Converts Aave v3 Horizon aggregate metrics into the common solvency representation.
    /// @dev This is the protocol-specific core of the invariant for Aave v3 Horizon: an account with debt is
    ///      solvent iff `healthFactor >= 1e18`.
    /// @param state Aggregate Aave v3 account state whose metadata contains health-factor inputs.
    /// @return solvency Common solvency output expressed in terms of health factor.
    function _evaluateHealthFactor(AccountState memory state) internal pure returns (SolvencyState memory solvency) {
        AaveAccountMetrics memory metrics = abi.decode(state.metadata, (AaveAccountMetrics));

        solvency.isSolvent = !state.hasDebt || metrics.healthFactor >= HEALTH_FACTOR_THRESHOLD;
        solvency.isLiquidatable = state.hasDebt && metrics.healthFactor < HEALTH_FACTOR_THRESHOLD;
        solvency.metricName = HEALTH_FACTOR_METRIC;
        solvency.metric = _toInt256(metrics.healthFactor);
        solvency.threshold = HEALTH_FACTOR_THRESHOLD_INT;
        solvency.comparison = ComparisonKind.Gte;
        solvency.metadata = abi.encode(metrics.availableBorrowsBase, metrics.currentLiquidationThreshold, metrics.ltv);
    }

    /// @notice Builds a single reserve-level balance entry for the account.
    /// @dev Returns `(false, ...)` when the account has neither supplied balance nor variable debt in
    ///      the reserve, allowing the caller to compact the final array. This example intentionally
    ///      follows the local Horizon borrow surface, which only exposes variable-rate borrowing.
    /// @param asset The reserve asset being inspected.
    /// @param account The account whose reserve position should be read.
    /// @param userConfigData Aave v3 user-configuration bitset used to determine collateral usage.
    /// @param oracle Price oracle used to value the reserve balances.
    /// @param fork The snapshot fork to query.
    /// @return include Whether the resulting balance entry should be kept.
    /// @return balance Normalized reserve-level balance information.
    function _buildAccountBalance(
        address asset,
        address account,
        uint256 userConfigData,
        address oracle,
        PhEvm.ForkId memory fork
    ) internal view returns (bool include, AccountBalance memory balance) {
        AaveV3Types.ReserveDataLegacy memory reserveData = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3PoolLike.getReserveData, (asset)), fork),
            (AaveV3Types.ReserveDataLegacy)
        );

        uint256 collateralBalance =
            _readUintAt(reserveData.aTokenAddress, abi.encodeCall(IERC20MetadataLike.balanceOf, (account)), fork);
        uint256 debtBalance = _readUintAt(
            reserveData.variableDebtTokenAddress, abi.encodeCall(IERC20MetadataLike.balanceOf, (account)), fork
        );

        if (collateralBalance == 0 && debtBalance == 0) {
            return (false, balance);
        }

        bool countsAsCollateral = collateralBalance != 0 && _isUsingAsCollateral(userConfigData, reserveData.id);

        balance = AccountBalance({
            asset: asset,
            collateralBalance: collateralBalance,
            debtBalance: debtBalance,
            collateralValue: countsAsCollateral ? _valueInBase(oracle, asset, collateralBalance, fork) : 0,
            debtValue: debtBalance == 0 ? 0 : _valueInBase(oracle, asset, debtBalance, fork),
            countsAsCollateral: countsAsCollateral,
            metadata: abi.encode(reserveData.id)
        });

        return (true, balance);
    }

    /// @notice Reads Aave v3 Horizon reserve metadata for a single asset at the requested snapshot fork.
    /// @param asset The reserve asset whose metadata should be queried.
    /// @param fork The snapshot fork to query.
    /// @return reserveData Reserve metadata returned by `Pool.getReserveData(...)`.
    function _getReserveData(address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (AaveV3Types.ReserveDataLegacy memory reserveData)
    {
        reserveData = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3PoolLike.getReserveData, (asset)), fork),
            (AaveV3Types.ReserveDataLegacy)
        );
    }

    /// @notice Reads the user's total debt for one reserve from Aave v3 Horizon debt-token balances.
    /// @dev The example sums stable and variable debt token balances to make the liquidation bound
    ///      robust across reserve configurations.
    /// @param asset The reserve asset whose debt position should be queried.
    /// @param account The user whose debt should be read.
    /// @param fork The snapshot fork to query.
    /// @return debtBalance Total reserve debt for the user.
    function _getUserReserveDebt(address asset, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 debtBalance)
    {
        AaveV3Types.ReserveDataLegacy memory reserveData = _getReserveData(asset, fork);
        debtBalance = _readOptionalBalance(reserveData.stableDebtTokenAddress, account, fork)
            + _readOptionalBalance(reserveData.variableDebtTokenAddress, account, fork);
    }

    /// @notice Reads a token balance when the token address may be unset.
    /// @dev Some deployments disable one debt-token flavor and leave the corresponding address at
    ///      zero. This helper treats that case as a zero balance instead of reverting.
    /// @param token The token contract to query, or `address(0)` when absent.
    /// @param account The account whose balance should be read.
    /// @param fork The snapshot fork to query.
    /// @return balance The token balance, or zero when `token == address(0)`.
    function _readOptionalBalance(address token, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        if (token == address(0)) {
            return 0;
        }

        return _readBalanceAt(token, account, fork);
    }

    /// @notice Converts an asset-denominated balance into Aave base currency.
    /// @dev Uses the Aave v3 Horizon oracle price and token decimals from the snapshot fork. This helper is
    ///      suitable for example code and debugging, but suites with stricter precision requirements
    ///      may want protocol-exact valuation logic.
    /// @param oracle Aave v3 price oracle.
    /// @param asset Asset whose price and decimals should be read.
    /// @param balance Raw token amount to convert.
    /// @param fork The snapshot fork to query.
    /// @return value Asset value expressed in Aave base currency units.
    function _valueInBase(address oracle, address asset, uint256 balance, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        uint256 price = _readUintAt(oracle, abi.encodeCall(IAaveV3OracleLike.getAssetPrice, (asset)), fork);
        uint8 decimals = _readUint8At(asset, abi.encodeCall(IERC20MetadataLike.decimals, ()), fork);
        return ph.mulDivDown(balance, price, 10 ** uint256(decimals));
    }

    /// @notice Returns whether the reserve is enabled as collateral in Aave v3 Horizon's user config bitset.
    /// @dev Aave v3 Horizon stores collateral and borrow flags as packed bit pairs keyed by reserve id. This
    ///      helper reads the collateral bit for the reserve.
    /// @param userConfigData Packed Aave v3 user configuration.
    /// @param reserveId Reserve id from `getReserveData(...)`.
    /// @return isCollateral True when the reserve currently counts as collateral.
    function _isUsingAsCollateral(uint256 userConfigData, uint256 reserveId) internal pure returns (bool) {
        return ((userConfigData >> (reserveId * 2)) & 1) != 0;
    }

    /// @notice Safely casts a `uint256` metric to `int256` for `SolvencyState`.
    /// @dev Solvency metrics use signed integers in the common interface to support protocols with
    ///      negative liquidity margins. Aave v3 health factor is always non-negative, so values above
    ///      `int256.max` are saturated instead of reverting.
    /// @param value Unsigned metric value to convert.
    /// @return signedValue Saturated signed representation of `value`.
    function _toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) {
            return type(int256).max;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }
}

/// @title AaveV3HorizonOperationSafetyAssertion
/// @author Phylax Systems
/// @notice Example single-entry assertion bundle for Aave v3 Horizon.
/// @dev Usage:
///      `cl.assertion({ adopter: aaveV3HorizonPool, createData: abi.encodePacked(type(AaveV3HorizonOperationSafetyAssertion).creationCode, abi.encode(aaveV3HorizonPool)), fnSelector: AaveV3HorizonOperationSafetyAssertion.assertOperationSafety.selector })`
contract AaveV3HorizonOperationSafetyAssertion is LendingBaseAssertion {
    /// @notice Dedicated Horizon suite deployed by this assertion bundle.
    /// @dev Keeping the suite in a helper contract preserves the one-create-data UX while keeping
    ///      the assertion runtime below the EIP-170 size limit enforced by CI.
    ILendingProtectionSuite internal immutable SUITE;

    /// @notice Creates an Aave v3 Horizon assertion bundle with an internally deployed suite.
    /// @param pool_ Aave v3 Horizon pool used both as the suite data source and assertion adopter.
    constructor(address pool_) {
        SUITE = ILendingProtectionSuite(address(new AaveV3HorizonProtectionSuite(pool_)));
    }

    /// @notice Returns the suite implementation used by the generic lending assertion base.
    /// @dev The assertion keeps protocol-specific logic in a dedicated helper suite contract so the
    ///      assertion runtime stays within CI's contract-size limit.
    /// @return suite The internally deployed common lending suite implementation.
    function _suite() internal view override returns (ILendingProtectionSuite) {
        return SUITE;
    }
}

/// @title AaveV3ProtectionSuite
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 suite name.
/// @dev The implementation is Horizon-specific and derived from the local Horizon repository.
contract AaveV3ProtectionSuite is AaveV3HorizonProtectionSuite {
    /// @notice Creates the compatibility alias.
    /// @param pool_ Aave v3 Horizon pool used by the underlying suite.
    constructor(address pool_) AaveV3HorizonProtectionSuite(pool_) {}
}

/// @title AaveV3OperationSafetyAssertion
/// @author Phylax Systems
/// @notice Compatibility alias preserving the old generic Aave v3 assertion name.
/// @dev New users should prefer `AaveV3HorizonOperationSafetyAssertion` to make the Horizon scope explicit.
contract AaveV3OperationSafetyAssertion is AaveV3HorizonOperationSafetyAssertion {
    /// @notice Creates the compatibility alias.
    /// @param pool_ Aave v3 Horizon pool used by the underlying assertion bundle.
    constructor(address pool_) AaveV3HorizonOperationSafetyAssertion(pool_) {}
}

/// @title AaveV3PostOperationSolvencyAssertion
/// @author Phylax Systems
/// @notice Deprecated compatibility alias for the pre-operation-safety contract name.
/// @dev New users should prefer `AaveV3HorizonOperationSafetyAssertion`.
contract AaveV3PostOperationSolvencyAssertion is AaveV3HorizonOperationSafetyAssertion {
    /// @notice Creates the deprecated compatibility alias.
    /// @param pool_ Aave v3 Horizon pool used by the underlying assertion bundle.
    constructor(address pool_) AaveV3HorizonOperationSafetyAssertion(pool_) {}
}
