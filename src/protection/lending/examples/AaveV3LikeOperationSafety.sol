// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {ILendingProtectionSuite} from "../ILendingProtectionSuite.sol";
import {LendingBaseAssertion, LendingProtectionSuiteBase} from "../LendingBaseAssertion.sol";
import {
    AaveV3LikeTypes,
    IAaveV3LikeAddressesProvider,
    IAaveV3LikeOracle,
    IAaveV3LikePool,
    IERC20MetadataLike
} from "./AaveV3LikeInterfaces.sol";

/// @title AaveV3LikeProtectionSuite
/// @author Phylax Systems
/// @notice Shared `ILendingProtectionSuite` implementation for Aave v3-compatible lending forks.
/// @dev This adapter matches the interface and accounting model used by forks such as the local
///      Aave v3 Horizon deployment and SparkLend v1.
contract AaveV3LikeProtectionSuite is LendingProtectionSuiteBase {
    /// @notice Extra aggregate Aave v3-like metrics kept in `AccountState.metadata`.
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

    /// @notice Creates an Aave v3-like suite bound to a specific pool.
    /// @param pool_ Pool address whose accounting and selectors this suite targets.
    constructor(address pool_) {
        POOL = pool_;
        ADDRESSES_PROVIDER = IAaveV3LikePool(pool_).ADDRESSES_PROVIDER();
    }

    /// @notice Returns the Aave v3-like pool selectors relevant to the shared lending invariants.
    function getMonitoredSelectors() external pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IAaveV3LikePool.borrow.selector;
        selectors[1] = IAaveV3LikePool.withdraw.selector;
        selectors[2] = IAaveV3LikePool.liquidationCall.selector;
        selectors[3] = IAaveV3LikePool.setUserUseReserveAsCollateral.selector;
        selectors[4] = IAaveV3LikePool.finalizeTransfer.selector;
    }

    /// @notice Decodes an Aave v3-like pool call into the shared lending operation model.
    function decodeOperation(TriggeredCall calldata triggered)
        external
        pure
        override
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;

        if (triggered.selector == IAaveV3LikePool.borrow.selector) {
            (address asset, uint256 amount,,, address onBehalfOf) =
                abi.decode(triggered.input[4:], (address, uint256, uint256, uint16, address));

            operation.kind = OperationKind.Borrow;
            operation.account = onBehalfOf;
            operation.asset = asset;
            operation.amount = amount;
            operation.increasesDebt = amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.withdraw.selector) {
            (address asset, uint256 amount, address to) = abi.decode(triggered.input[4:], (address, uint256, address));

            operation.kind = OperationKind.WithdrawCollateral;
            operation.account = triggered.caller;
            operation.asset = asset;
            operation.counterparty = to;
            operation.amount = amount;
            operation.reducesEffectiveCollateral = amount != 0;
            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.liquidationCall.selector) {
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

        if (triggered.selector == IAaveV3LikePool.setUserUseReserveAsCollateral.selector) {
            (address asset, bool useAsCollateral) = abi.decode(triggered.input[4:], (address, bool));

            if (!useAsCollateral) {
                operation.kind = OperationKind.DisableCollateral;
                operation.account = triggered.caller;
                operation.asset = asset;
                operation.reducesEffectiveCollateral = true;
            }

            return operation;
        }

        if (triggered.selector == IAaveV3LikePool.finalizeTransfer.selector) {
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

    /// @notice Filters decoded Aave v3-like operations down to the ones that must preserve solvency.
    function shouldCheckPostOperationSolvency(OperationContext calldata operation)
        external
        pure
        override
        returns (bool shouldCheck)
    {
        return operation.account != address(0) && (operation.increasesDebt || operation.reducesEffectiveCollateral);
    }

    /// @notice Returns the bounded-consumption checks implied by the decoded Aave v3-like operation.
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

    /// @notice Reads the post-call snapshot needed by the health-factor solvency invariant.
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

    /// @notice Reads aggregate account metrics from `Pool.getUserAccountData(...)`.
    function getAccountState(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountState memory state)
    {
        return _getAccountState(account, fork);
    }

    /// @notice Enumerates reserve balances for the account.
    function getAccountBalances(address account, PhEvm.ForkId calldata fork)
        external
        view
        override
        returns (AccountBalance[] memory balances)
    {
        return _getAccountBalances(account, fork);
    }

    /// @notice Evaluates solvency from aggregate account state.
    function evaluateSolvency(
        AccountState calldata state,
        AccountBalance[] calldata balances,
        PhEvm.ForkId calldata fork
    ) external pure override returns (SolvencyState memory solvency) {
        balances;
        fork;
        return _evaluateHealthFactor(state);
    }

    /// @notice Internal helper that reads and normalizes aggregate account data.
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
            _viewAt(POOL, abi.encodeCall(IAaveV3LikePool.getUserAccountData, (account)), fork),
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
    function _getAccountBalances(address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (AccountBalance[] memory balances)
    {
        address[] memory reserves =
            abi.decode(_viewAt(POOL, abi.encodeCall(IAaveV3LikePool.getReservesList, ()), fork), (address[]));
        AaveV3LikeTypes.UserConfigurationMap memory userConfig = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3LikePool.getUserConfiguration, (account)), fork),
            (AaveV3LikeTypes.UserConfigurationMap)
        );

        address oracle =
            _readAddressAt(ADDRESSES_PROVIDER, abi.encodeCall(IAaveV3LikeAddressesProvider.getPriceOracle, ()), fork);

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

    /// @notice Builds the withdraw bounded-consumption check from call output and pre-state.
    function _getWithdrawClaimCheck(
        TriggeredCall calldata triggered,
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork
    ) internal view returns (ConsumptionCheck memory check) {
        AaveV3LikeTypes.ReserveData memory reserveData = _getReserveData(operation.asset, beforeFork);
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
    function _getLiquidationDebtCheck(
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) internal view returns (ConsumptionCheck memory check) {
        AaveV3LikeTypes.ReserveData memory reserveData = _getReserveData(operation.asset, beforeFork);
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
    function _getLiquidationCollateralCheck(
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) internal view returns (ConsumptionCheck memory check) {
        bool receiveAToken = abi.decode(operation.metadata, (bool));
        AaveV3LikeTypes.ReserveData memory reserveData = _getReserveData(operation.relatedAsset, beforeFork);
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

    /// @notice Converts aggregate metrics into the common solvency representation.
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
    function _buildAccountBalance(
        address asset,
        address account,
        uint256 userConfigData,
        address oracle,
        PhEvm.ForkId memory fork
    ) internal view returns (bool include, AccountBalance memory balance) {
        AaveV3LikeTypes.ReserveData memory reserveData = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3LikePool.getReserveData, (asset)), fork), (AaveV3LikeTypes.ReserveData)
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

    /// @notice Reads reserve metadata for a single asset at the requested snapshot fork.
    function _getReserveData(address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (AaveV3LikeTypes.ReserveData memory reserveData)
    {
        reserveData = abi.decode(
            _viewAt(POOL, abi.encodeCall(IAaveV3LikePool.getReserveData, (asset)), fork), (AaveV3LikeTypes.ReserveData)
        );
    }

    /// @notice Reads the user's total debt for one reserve from the debt-token balances.
    function _getUserReserveDebt(address asset, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 debtBalance)
    {
        AaveV3LikeTypes.ReserveData memory reserveData = _getReserveData(asset, fork);
        debtBalance = _readOptionalBalance(reserveData.stableDebtTokenAddress, account, fork)
            + _readOptionalBalance(reserveData.variableDebtTokenAddress, account, fork);
    }

    /// @notice Reads a token balance when the token address may be unset.
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

    /// @notice Converts an asset-denominated balance into the pool base currency.
    function _valueInBase(address oracle, address asset, uint256 balance, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        uint256 price = _readUintAt(oracle, abi.encodeCall(IAaveV3LikeOracle.getAssetPrice, (asset)), fork);
        uint8 decimals = _readUint8At(asset, abi.encodeCall(IERC20MetadataLike.decimals, ()), fork);
        return ph.mulDivDown(balance, price, 10 ** uint256(decimals));
    }

    /// @notice Returns whether the reserve is enabled as collateral in the user config bitset.
    function _isUsingAsCollateral(uint256 userConfigData, uint256 reserveId) internal pure returns (bool) {
        return ((userConfigData >> (reserveId * 2)) & 1) != 0;
    }

    /// @notice Safely casts a `uint256` metric to `int256` for `SolvencyState`.
    function _toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) {
            return type(int256).max;
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }
}

/// @title AaveV3LikeOperationSafetyAssertionBase
/// @author Phylax Systems
/// @notice Shared assertion wrapper for Aave v3-like lending suites.
abstract contract AaveV3LikeOperationSafetyAssertionBase is LendingBaseAssertion {
    ILendingProtectionSuite internal immutable SUITE;

    constructor(address suite_) {
        SUITE = ILendingProtectionSuite(suite_);
    }

    function _suite() internal view override returns (ILendingProtectionSuite) {
        return SUITE;
    }
}
