// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AaveV4Helpers} from "./AaveV4Helpers.sol";
import {IAaveV4Hub, IAaveV4Spoke} from "./AaveV4Interfaces.sol";

/// @title AaveV4SpokeRiskAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for one Aave v4 Spoke.
/// @dev Protects oracle-backed, cross-contract risk state that is not just a local `require`:
///      - Recomputes account data independently from reserves, user positions, Hub indices, and
///        oracle prices, then compares it with the Spoke's public account view.
///      - Checks stored risk premium only on paths that are supposed to refresh premium state.
///      - Bounds reserve oracle movement across risk-changing calls.
///      - Checks liquidation reduces borrower risk using independently recomputed account data.
contract AaveV4SpokeRiskAssertion is AaveV4Helpers {
    struct CollateralItem {
        uint256 risk;
        uint256 value;
    }

    struct ReserveContribution {
        bool activeCollateral;
        uint256 collateralRisk;
        uint256 collateralValue;
        uint256 weightedCollateralFactor;
        bool borrowing;
        uint256 debtValueRay;
    }

    address internal immutable SPOKE;
    uint256 internal immutable MAX_RESERVES_TO_SCAN;
    uint256 internal immutable ORACLE_DEVIATION_BPS;

    constructor(address spoke_, uint256 maxReservesToScan_, uint256 oracleDeviationBps_) {
        require(spoke_ != address(0), "AaveV4Spoke: spoke zero");
        require(maxReservesToScan_ > 0, "AaveV4Spoke: max reserves zero");
        require(oracleDeviationBps_ <= BPS, "AaveV4Spoke: bad oracle tolerance");

        SPOKE = spoke_;
        MAX_RESERVES_TO_SCAN = maxReservesToScan_;
        ORACLE_DEVIATION_BPS = oracleDeviationBps_;
    }

    /// @notice Registers Spoke operations that modify oracle-backed account risk.
    /// @dev Calls that intentionally refresh stored risk premium are distinguished from paths
    ///      that only change collateral composition without refreshing premium debt.
    function triggers() external view override {
        registerFnCallTrigger(this.assertAccountDataMatchesIndependentState.selector, IAaveV4Spoke.withdraw.selector);
        registerFnCallTrigger(this.assertAccountDataMatchesIndependentState.selector, IAaveV4Spoke.borrow.selector);
        registerFnCallTrigger(
            this.assertAccountDataMatchesIndependentState.selector, IAaveV4Spoke.setUsingAsCollateral.selector
        );
        registerFnCallTrigger(
            this.assertAccountDataMatchesIndependentState.selector, IAaveV4Spoke.updateUserRiskPremium.selector
        );
        registerFnCallTrigger(
            this.assertAccountDataMatchesIndependentState.selector, IAaveV4Spoke.updateUserDynamicConfig.selector
        );
        registerFnCallTrigger(
            this.assertAccountDataMatchesIndependentState.selector, IAaveV4Spoke.liquidationCall.selector
        );

        registerFnCallTrigger(
            this.assertLiquidationImprovesBorrowerRisk.selector, IAaveV4Spoke.liquidationCall.selector
        );
    }

    /// @notice Recomputes account data from primitive state and compares it to the Spoke view.
    /// @dev The recomputation enumerates reserves, reads user positions, dynamic configs, Hub
    ///      drawn indices, Hub supply conversions, and oracle prices at the post-call fork. A
    ///      failure means the public account data or stored risk premium no longer follows the
    ///      cross-contract state that liquidations and borrow safety depend on.
    function assertAccountDataMatchesIndependentState() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireAdopter(SPOKE, "AaveV4Spoke: configured spoke is not adopter");

        (address user, bool shouldCheckStoredRiskPremium) =
            _accountDataUser(ctx.selector, ph.callinputAt(ctx.callStart));
        PhEvm.ForkId memory pre = _preCall(ctx.callStart);
        PhEvm.ForkId memory post = _postCall(ctx.callEnd);

        _assertOraclePricesBounded(pre, post);

        IAaveV4Spoke.UserAccountData memory expected = _recomputeAccountDataAt(user, post);
        IAaveV4Spoke.UserAccountData memory actual = _spokeAccountDataAt(SPOKE, user, post);
        _assertAccountDataEqual(expected, actual);

        if (shouldCheckStoredRiskPremium) {
            uint256 storedRiskPremium = _spokeLastRiskPremiumAt(SPOKE, user, post);
            require(storedRiskPremium == expected.riskPremium, "AaveV4Spoke: stored risk premium mismatch");
        }
    }

    /// @notice Checks liquidation reduces borrower risk.
    /// @dev Compares independently recomputed account data around a successful liquidation. Debt
    ///      may be fully cleared or reported as deficit; otherwise post-liquidation debt must not
    ///      increase and health factor must not be worse than before liquidation.
    function assertLiquidationImprovesBorrowerRisk() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireAdopter(SPOKE, "AaveV4Spoke: configured spoke is not adopter");

        (,, address user,,) =
            abi.decode(_args(ph.callinputAt(ctx.callStart)), (uint256, uint256, address, uint256, bool));

        IAaveV4Spoke.UserAccountData memory beforeData = _recomputeAccountDataAt(user, _preCall(ctx.callStart));
        IAaveV4Spoke.UserAccountData memory afterData = _recomputeAccountDataAt(user, _postCall(ctx.callEnd));

        if (beforeData.healthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD || afterData.totalDebtValueRay == 0) {
            return;
        }

        require(afterData.totalDebtValueRay <= beforeData.totalDebtValueRay, "AaveV4Spoke: liquidation increased debt");
        require(afterData.healthFactor >= beforeData.healthFactor, "AaveV4Spoke: liquidation health factor worsened");
    }

    function _recomputeAccountDataAt(address user, PhEvm.ForkId memory fork)
        internal
        view
        returns (IAaveV4Spoke.UserAccountData memory accountData)
    {
        uint256 reserveCount = _readUintAt(SPOKE, abi.encodeCall(IAaveV4Spoke.getReserveCount, ()), fork);
        require(reserveCount <= MAX_RESERVES_TO_SCAN, "AaveV4Spoke: too many reserves");

        address oracle = _readAddressAt(SPOKE, abi.encodeCall(IAaveV4Spoke.ORACLE, ()), fork);
        CollateralItem[] memory collateralItems = new CollateralItem[](reserveCount);

        for (uint256 reserveId; reserveId < reserveCount; ++reserveId) {
            ReserveContribution memory contribution = _reserveContributionAt(user, reserveId, oracle, fork);
            if (contribution.activeCollateral) {
                accountData.totalCollateralValue += contribution.collateralValue;
                accountData.avgCollateralFactor += contribution.weightedCollateralFactor;
                collateralItems[accountData.activeCollateralCount] =
                    CollateralItem({risk: contribution.collateralRisk, value: contribution.collateralValue});
                accountData.activeCollateralCount++;
            }

            if (contribution.borrowing) {
                accountData.totalDebtValueRay += contribution.debtValueRay;
                accountData.borrowCount++;
            }
        }

        accountData.healthFactor = _healthFactor(accountData.avgCollateralFactor, accountData.totalDebtValueRay);
        if (accountData.totalCollateralValue > 0) {
            accountData.avgCollateralFactor =
                (accountData.avgCollateralFactor * (WAD / BPS)) / accountData.totalCollateralValue;
        }
        accountData.riskPremium =
            _riskPremium(collateralItems, accountData.activeCollateralCount, accountData.totalDebtValueRay);
    }

    function _reserveContributionAt(address user, uint256 reserveId, address oracle, PhEvm.ForkId memory fork)
        internal
        view
        returns (ReserveContribution memory contribution)
    {
        IAaveV4Spoke.Reserve memory reserve = _spokeReserveAt(SPOKE, reserveId, fork);
        IAaveV4Spoke.UserPosition memory position = _spokeUserPositionAt(SPOKE, reserveId, user, fork);
        (bool collateral, bool borrowing) = _spokeUserReserveStatusAt(SPOKE, reserveId, user, fork);
        uint256 price = _oraclePriceAt(oracle, reserveId, fork);
        require(price > 0, "AaveV4Spoke: oracle price invalid");

        if (collateral) {
            (contribution.activeCollateral, contribution.collateralValue, contribution.weightedCollateralFactor) =
                _collateralContribution(reserveId, reserve, position, price, fork);
            contribution.collateralRisk = reserve.collateralRisk;
        }

        if (borrowing) {
            contribution.borrowing = true;
            contribution.debtValueRay = _debtValueRay(reserve, position, price, fork);
        }
    }

    function _collateralContribution(
        uint256 reserveId,
        IAaveV4Spoke.Reserve memory reserve,
        IAaveV4Spoke.UserPosition memory position,
        uint256 price,
        PhEvm.ForkId memory fork
    ) internal view returns (bool active, uint256 collateralValue, uint256 weightedFactor) {
        IAaveV4Spoke.DynamicReserveConfig memory config =
            _spokeDynamicConfigAt(SPOKE, reserveId, position.dynamicConfigKey, fork);
        if (config.collateralFactor == 0 || position.suppliedShares == 0) {
            return (false, 0, 0);
        }

        uint256 suppliedAssets =
            _hubPreviewRemoveBySharesAt(reserve.hub, reserve.assetId, position.suppliedShares, fork);
        collateralValue = _toValue(suppliedAssets, reserve.decimals, price);
        weightedFactor = collateralValue * config.collateralFactor;
        active = true;
    }

    function _debtValueRay(
        IAaveV4Spoke.Reserve memory reserve,
        IAaveV4Spoke.UserPosition memory position,
        uint256 price,
        PhEvm.ForkId memory fork
    ) internal view returns (uint256) {
        uint256 drawnIndex = _hubDrawnIndexAt(reserve.hub, reserve.assetId, fork);
        uint256 premiumDebtRay = _premiumDebtRay(position.premiumShares, position.premiumOffsetRay, drawnIndex);
        uint256 debtRay = uint256(position.drawnShares) * drawnIndex + premiumDebtRay;
        return _toValue(debtRay, reserve.decimals, price);
    }

    function _assertAccountDataEqual(
        IAaveV4Spoke.UserAccountData memory expected,
        IAaveV4Spoke.UserAccountData memory actual
    ) internal pure {
        require(actual.riskPremium == expected.riskPremium, "AaveV4Spoke: account risk premium mismatch");
        require(actual.avgCollateralFactor == expected.avgCollateralFactor, "AaveV4Spoke: account CF mismatch");
        require(actual.healthFactor == expected.healthFactor, "AaveV4Spoke: account health factor mismatch");
        require(
            actual.totalCollateralValue == expected.totalCollateralValue, "AaveV4Spoke: account collateral mismatch"
        );
        require(actual.totalDebtValueRay == expected.totalDebtValueRay, "AaveV4Spoke: account debt mismatch");
        require(
            actual.activeCollateralCount == expected.activeCollateralCount,
            "AaveV4Spoke: active collateral count mismatch"
        );
        require(actual.borrowCount == expected.borrowCount, "AaveV4Spoke: borrow count mismatch");
    }

    function _premiumDebtRay(uint256 premiumShares, int256 premiumOffsetRay, uint256 drawnIndex)
        internal
        pure
        returns (uint256)
    {
        int256 premiumRay = int256(premiumShares * drawnIndex) - premiumOffsetRay;
        require(premiumRay >= 0, "AaveV4Spoke: negative premium debt");
        return uint256(premiumRay);
    }

    function _healthFactor(uint256 weightedCollateralFactor, uint256 totalDebtValueRay)
        internal
        pure
        returns (uint256)
    {
        if (totalDebtValueRay == 0) {
            return type(uint256).max;
        }
        return ((weightedCollateralFactor * (WAD / BPS)) * RAY) / totalDebtValueRay;
    }

    function _riskPremium(CollateralItem[] memory items, uint256 length, uint256 totalDebtValueRay)
        internal
        pure
        returns (uint256)
    {
        if (totalDebtValueRay == 0 || length == 0) {
            return 0;
        }

        _sortCollateralItems(items, length);

        uint256 totalDebtValue = _fromRayUp(totalDebtValueRay);
        uint256 debtLeft = totalDebtValue;
        uint256 weightedRisk;
        uint256 coveredDebt;

        for (uint256 i; i < length && debtLeft != 0; ++i) {
            uint256 used = items[i].value < debtLeft ? items[i].value : debtLeft;
            weightedRisk += used * items[i].risk;
            debtLeft -= used;
            coveredDebt += used;
        }

        if (coveredDebt == 0) {
            return 0;
        }
        return _divUp(weightedRisk, coveredDebt);
    }

    function _sortCollateralItems(CollateralItem[] memory items, uint256 length) internal pure {
        for (uint256 i = 1; i < length; ++i) {
            CollateralItem memory item = items[i];
            uint256 j = i;
            while (j > 0 && _comesBefore(item, items[j - 1])) {
                items[j] = items[j - 1];
                --j;
            }
            items[j] = item;
        }
    }

    function _comesBefore(CollateralItem memory a, CollateralItem memory b) internal pure returns (bool) {
        return a.risk < b.risk || (a.risk == b.risk && a.value > b.value);
    }

    function _assertOraclePricesBounded(PhEvm.ForkId memory pre, PhEvm.ForkId memory post) internal view {
        uint256 reserveCount = _readUintAt(SPOKE, abi.encodeCall(IAaveV4Spoke.getReserveCount, ()), post);
        require(reserveCount <= MAX_RESERVES_TO_SCAN, "AaveV4Spoke: too many reserves");

        address oracle = _readAddressAt(SPOKE, abi.encodeCall(IAaveV4Spoke.ORACLE, ()), post);
        for (uint256 reserveId; reserveId < reserveCount; ++reserveId) {
            uint256 prePrice = _oraclePriceAt(oracle, reserveId, pre);
            uint256 postPrice = _oraclePriceAt(oracle, reserveId, post);
            require(prePrice > 0 && postPrice > 0, "AaveV4Spoke: oracle price invalid");

            require(
                ph.ratioGe(postPrice, 1, prePrice, 1, ORACLE_DEVIATION_BPS)
                    && ph.ratioGe(prePrice, 1, postPrice, 1, ORACLE_DEVIATION_BPS),
                "AaveV4Spoke: oracle price drift"
            );
        }
    }

    function _accountDataUser(bytes4 selector, bytes memory input)
        internal
        pure
        returns (address user, bool shouldCheckStoredRiskPremium)
    {
        if (selector == IAaveV4Spoke.borrow.selector || selector == IAaveV4Spoke.withdraw.selector) {
            (,, user) = abi.decode(_args(input), (uint256, uint256, address));
            return (user, true);
        }

        if (selector == IAaveV4Spoke.setUsingAsCollateral.selector) {
            (, bool usingAsCollateral, address onBehalfOf) = abi.decode(_args(input), (uint256, bool, address));
            return (onBehalfOf, !usingAsCollateral);
        }

        if (selector == IAaveV4Spoke.updateUserRiskPremium.selector) {
            user = abi.decode(_args(input), (address));
            return (user, true);
        }

        if (selector == IAaveV4Spoke.updateUserDynamicConfig.selector) {
            user = abi.decode(_args(input), (address));
            return (user, true);
        }

        if (selector == IAaveV4Spoke.liquidationCall.selector) {
            (,, user,,) = abi.decode(_args(input), (uint256, uint256, address, uint256, bool));
            return (user, true);
        }
    }
}
