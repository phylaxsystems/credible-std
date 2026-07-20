// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {LendingProtectionSuiteBase} from "../LendingBaseAssertion.sol";
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
///
///      The suite protects the lending surface that can directly worsen an account:
///      - new borrows and collateral withdrawals must leave the account above Aave's health-factor
///        liquidation threshold;
///      - disabling collateral, transferring aTokens, or changing e-mode must not turn a healthy
///        account into a liquidatable one;
///      - withdrawals and liquidations are bounded by the user's pre-call claim, debt, and collateral
///        so a locally successful call cannot consume more value than the pre-state allowed.
///
///      These checks intentionally use the pool's own `getUserAccountData` output as the risk source
///      of truth. A failure means the transaction passed protocol execution but left external lending
///      accounting in a state users would experience as bad debt, over-withdrawal, or over-liquidation.
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
    /// @param addressesProvider_ The pool's `ADDRESSES_PROVIDER`. Passed in explicitly because
    ///        assertions are deployed against an empty state where calling the pool would fail.
    constructor(address pool_, address addressesProvider_) {
        POOL = pool_;
        ADDRESSES_PROVIDER = addressesProvider_;
    }

    /// @notice Returns the Aave v3-like pool selectors relevant to the shared lending invariants.
    /// @dev The list is intentionally limited to operations that can change debt, effective
    ///      collateral, liquidation settlement, or the user's risk category. Supply, repay, and other
    ///      risk-improving paths are left out to keep the example focused and low noise.
    function getMonitoredSelectors() external pure virtual override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IAaveV3LikePool.borrow.selector;
        selectors[1] = IAaveV3LikePool.withdraw.selector;
        selectors[2] = IAaveV3LikePool.liquidationCall.selector;
        selectors[3] = IAaveV3LikePool.setUserUseReserveAsCollateral.selector;
        selectors[4] = IAaveV3LikePool.finalizeTransfer.selector;
        selectors[5] = IAaveV3LikePool.setUserEMode.selector;
    }

    /// @notice Decodes an Aave v3-like pool call into the shared lending operation model.
    /// @dev The generic lending base only needs a normalized operation: whose risk changed, which
    ///      asset moved, and whether the call increased debt or reduced effective collateral. Keeping
    ///      the Aave ABI details here lets the base assertion express protocol-agnostic safety rules.
    function decodeOperation(TriggeredCall calldata triggered)
        external
        view
        virtual
        override
        returns (OperationContext memory operation)
    {
        if (triggered.selector == IAaveV3LikePool.borrow.selector) {
            return _decodeBorrowOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.withdraw.selector) {
            return _decodeWithdrawOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.liquidationCall.selector) {
            return _decodeLiquidationOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.setUserUseReserveAsCollateral.selector) {
            return _decodeCollateralToggleOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.finalizeTransfer.selector) {
            return _decodeFinalizeTransferOperation(triggered);
        }

        if (triggered.selector == IAaveV3LikePool.setUserEMode.selector) {
            return _decodeSetUserEModeOperation(triggered);
        }

        operation.selector = triggered.selector;
        operation.caller = triggered.caller;
        return operation;
    }

    function _baseOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        operation.selector = triggered.selector;
        operation.caller = triggered.caller;
    }

    function _decodeBorrowOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        (address asset, uint256 amount,,, address onBehalfOf) =
            abi.decode(triggered.input[4:], (address, uint256, uint256, uint16, address));

        operation = _baseOperation(triggered);
        operation.kind = OperationKind.Borrow;
        operation.account = onBehalfOf;
        operation.asset = asset;
        operation.amount = amount;
        operation.increasesDebt = amount != 0;
    }

    function _decodeWithdrawOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        (address asset, uint256 amount, address to) = abi.decode(triggered.input[4:], (address, uint256, address));

        operation = _baseOperation(triggered);
        operation.kind = OperationKind.WithdrawCollateral;
        operation.account = triggered.caller;
        operation.asset = asset;
        operation.counterparty = to;
        operation.amount = amount;
        operation.reducesEffectiveCollateral = amount != 0;
    }

    function _decodeLiquidationOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        (address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) =
            abi.decode(triggered.input[4:], (address, address, address, uint256, bool));

        operation = _baseOperation(triggered);
        operation.kind = OperationKind.Liquidation;
        operation.account = user;
        operation.asset = debtAsset;
        operation.relatedAsset = collateralAsset;
        operation.counterparty = triggered.caller;
        operation.amount = debtToCover;
        operation.metadata = abi.encode(receiveAToken);
    }

    function _decodeCollateralToggleOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        (address asset, bool useAsCollateral) = abi.decode(triggered.input[4:], (address, bool));

        operation = _baseOperation(triggered);
        if (!useAsCollateral) {
            operation.kind = OperationKind.DisableCollateral;
            operation.account = triggered.caller;
            operation.asset = asset;
            operation.reducesEffectiveCollateral = true;
        }
    }

    function _decodeFinalizeTransferOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        (address asset, address from, address to, uint256 amount,,) =
            abi.decode(triggered.input[4:], (address, address, address, uint256, uint256, uint256));

        operation = _baseOperation(triggered);
        operation.kind = OperationKind.TransferCollateral;
        operation.account = from;
        operation.asset = asset;
        operation.counterparty = to;
        operation.amount = amount;
        operation.reducesEffectiveCollateral = from != to && amount != 0;
    }

    function _decodeSetUserEModeOperation(TriggeredCall calldata triggered)
        internal
        pure
        returns (OperationContext memory operation)
    {
        (uint8 categoryId) = abi.decode(triggered.input[4:], (uint8));

        operation = _baseOperation(triggered);
        operation.kind = OperationKind.SetEMode;
        operation.account = triggered.caller;
        operation.amount = uint256(categoryId);
        operation.metadata = abi.encode(categoryId);
    }

    /// @notice Filters decoded Aave v3-like operations down to the ones that must preserve solvency.
    /// @dev A post-operation health-factor check is only meaningful for calls that can worsen the
    ///      account. This avoids tripping on harmless operations and makes each failure actionable:
    ///      a previously healthy account ended the triggering call below the liquidation threshold.
    function shouldCheckPostOperationSolvency(OperationContext calldata operation)
        external
        pure
        override
        returns (bool shouldCheck)
    {
        return operation.account != address(0)
            && (operation.increasesDebt
                || operation.reducesEffectiveCollateral
                || operation.kind == OperationKind.SetEMode);
    }

    /// @notice Returns the bounded-consumption checks implied by the decoded Aave v3-like operation.
    /// @dev Solvency alone does not catch value extraction bugs. These checks also assert that a
    ///      withdraw cannot return more assets than the caller's pre-call aToken claim, and that a
    ///      liquidation cannot repay/seize more debt or collateral than existed immediately before it.
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
    /// @dev The lending base calls this at precise pre-call and post-call forks. Using the same pool
    ///      aggregate view that integrators rely on makes the failure easy to interpret: the protocol's
    ///      own account data says the user is no longer solvent.
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
    /// @dev `withdraw` returns the actual asset amount sent. Comparing that return value with the
    ///      caller's pre-call aToken balance catches accounting bugs where a successful withdrawal
    ///      consumes more collateral claim than the account had before the call.
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
    /// @dev The liquidation input can request `type(uint256).max`, so the assertion observes the
    ///      actual debt-asset transfer instead of trusting calldata. A failure means the liquidator
    ///      repaid more debt than the borrower owed in the pre-call snapshot.
    function _getLiquidationDebtCheck(
        OperationContext calldata operation,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) internal view returns (ConsumptionCheck memory check) {
        AaveV3LikeTypes.ReserveData memory reserveData = _getReserveData(operation.asset, beforeFork);
        uint256 debtBefore = _getUserReserveDebt(operation.asset, operation.account, beforeFork);
        uint256 repaidEffective = _transferredValueDuringCall(
            operation.asset, operation.counterparty, reserveData.aTokenAddress, beforeFork, afterFork
        );

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
    /// @dev The seized side differs depending on `receiveAToken`: liquidators can receive aTokens or
    ///      underlying collateral. The check observes the token that actually moved and bounds it by
    ///      the borrower's pre-call collateral claim, protecting users from over-seizure.
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
        uint256 seizedEffective =
            _transferredValueDuringCall(seizedToken, transferSender, operation.counterparty, beforeFork, afterFork);

        check = ConsumptionCheck({
            checkName: LIQUIDATION_COLLATERAL_CHECK,
            account: operation.account,
            asset: operation.relatedAsset,
            availableBefore: collateralBefore,
            consumed: seizedEffective,
            metadata: abi.encode(reserveData.aTokenAddress, seizedToken, transferSender, receiveAToken)
        });
    }

    /// @notice Reads token movement for only the triggered call window.
    /// @dev ERC20 transfer precompiles return cumulative logs up to the requested fork, so subtract
    ///      the pre-call amount from the post-call amount to avoid counting earlier same-tx transfers.
    function _transferredValueDuringCall(
        address token,
        address from,
        address to,
        PhEvm.ForkId calldata beforeFork,
        PhEvm.ForkId calldata afterFork
    ) internal view returns (uint256 value) {
        uint256 beforeValue = _transferredValueAt(token, from, to, beforeFork);
        uint256 afterValue = _transferredValueAt(token, from, to, afterFork);

        return afterValue > beforeValue ? afterValue - beforeValue : 0;
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
        return ((userConfigData >> (reserveId * 2 + 1)) & 1) != 0;
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
