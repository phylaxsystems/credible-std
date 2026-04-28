// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {EulerEVaultBase} from "./EulerEVaultHelpers.sol";
import {IEulerEVaultLike} from "./EulerEVaultInterfaces.sol";

/// @title EulerUserStorageAccountingMixin
/// @author Phylax Systems
/// @notice Checks that modified EVK user storage remains consistent with public account views.
/// @dev Uses mapping tracing to find modified `vaultStorage.users[account]` entries without
///      decoding EVC batches or routers. This applies to Euler Vault Kit EVaults with the
///      storage layout documented in `EulerEVaultBase.USERS_MAPPING_SLOT`.
abstract contract EulerUserStorageAccountingMixin is EulerEVaultBase {
    function _registerUserStorageAccounting() internal view {
        registerTxEndTrigger(this.assertUserStorageMatchesAccountViews.selector);
    }

    /// @notice Verifies changed EVK user share/debt fields against direct public account views.
    /// @dev Runs once at tx end. A failure means EVK's packed user storage no longer agrees with
    ///      `balanceOf(account)` for shares or `debtOfExact(account)` for accounts whose debt slot
    ///      was refreshed during the transaction.
    function assertUserStorageMatchesAccountViews() external view {
        address vault = _vault();
        bytes[] memory keys = ph.changedMappingKeys(vault, USERS_MAPPING_SLOT);

        for (uint256 i; i < keys.length; ++i) {
            _assertChangedUserState(vault, keys[i]);
        }
    }

    function _assertChangedUserState(address vault, bytes memory key) internal view {
        address account = _keyToAddress(key);

        (bytes32 prePacked, bytes32 postPacked, bool dataChanged) =
            ph.mappingValueDiff(vault, USERS_MAPPING_SLOT, key, 0);
        (bytes32 preAcc, bytes32 postAcc, bool accumulatorChanged) =
            ph.mappingValueDiff(vault, USERS_MAPPING_SLOT, key, 1);

        if (!dataChanged && !accumulatorChanged) {
            return;
        }

        _assertShareState(vault, account, postPacked, dataChanged);
        _assertDebtState(vault, account, prePacked, postPacked, preAcc, postAcc, accumulatorChanged);
    }

    function _assertShareState(address vault, address account, bytes32 postPacked, bool dataChanged) internal view {
        if (!dataChanged) {
            return;
        }

        uint256 postBalance = _readBalanceAt(vault, account, _postTx());
        require(postBalance == _rawShares(postPacked), "EulerEVault: balanceOf != packed shares");
    }

    function _assertDebtState(
        address vault,
        address account,
        bytes32 prePacked,
        bytes32 postPacked,
        bytes32 preAcc,
        bytes32 postAcc,
        bool accumulatorChanged
    ) internal view {
        uint256 preRawOwed = _rawOwed(prePacked);
        uint256 postRawOwed = _rawOwed(postPacked);
        if (preRawOwed == postRawOwed && !accumulatorChanged) {
            return;
        }
        if (preRawOwed == postRawOwed && preAcc == postAcc) {
            return;
        }

        uint256 postDebtExact = _debtOfExactAt(vault, account, _postTx());
        require(postDebtExact == postRawOwed, "EulerEVault: debtOfExact != packed owed");
    }
}

/// @title EulerPerCallSharePriceMixin
/// @author Phylax Systems
/// @notice Ensures each EVK mutating call does not cause unexplained virtual share-price loss.
/// @dev EVK can reduce share price when debt is socialized. This assertion allows that case only
///      when a `DebtSocialized` event is emitted in the same call and the amount explains the drop.
abstract contract EulerPerCallSharePriceMixin is EulerEVaultBase {
    uint256 public immutable sharePriceToleranceBps;

    constructor(uint256 toleranceBps_) {
        sharePriceToleranceBps = toleranceBps_;
    }

    function _registerPerCallSharePrice() internal view {
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.deposit.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.mint.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.withdraw.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.redeem.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.skim.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.borrow.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.repay.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.repayWithShares.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.pullDebt.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.flashLoan.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.touch.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.liquidate.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.transfer.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.transferFrom.selector
        );
        registerFnCallTrigger(
            this.assertPerCallSharePriceDropOnlyFromSocialization.selector, IEulerEVaultLike.transferFromMax.selector
        );
    }

    /// @notice Checks call-scoped EVK virtual share price before and after a single adopter call.
    /// @dev A failure means one EVault call reduced `(totalAssets + 1e6) / (totalSupply + 1e6)`
    ///      beyond tolerance without same-call debt socialization explaining the loss.
    function assertPerCallSharePriceDropOnlyFromSocialization() external view {
        address vault = _vault();
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);

        uint256 preAssets = _totalAssetsAt(vault, beforeFork) + VIRTUAL_DEPOSIT_AMOUNT;
        uint256 preShares = _totalSupplyAt(vault, beforeFork) + VIRTUAL_DEPOSIT_AMOUNT;
        uint256 postAssets = _totalAssetsAt(vault, afterFork) + VIRTUAL_DEPOSIT_AMOUNT;
        uint256 postShares = _totalSupplyAt(vault, afterFork) + VIRTUAL_DEPOSIT_AMOUNT;

        if (ph.ratioGe(postAssets, postShares, preAssets, preShares, sharePriceToleranceBps)) {
            return;
        }

        uint256 socialized = _socializedDebtInCall(vault, ctx.callStart);
        require(socialized != 0, "EulerEVault: share price dropped without debt socialization");

        require(
            ph.ratioGe(postAssets + socialized, postShares, preAssets, preShares, sharePriceToleranceBps),
            "EulerEVault: share price drop exceeds socialized debt"
        );
    }

    function _socializedDebtInCall(address vault, uint256 callId) internal view returns (uint256 socialized) {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: DEBT_SOCIALIZED_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);

        for (uint256 i; i < logs.length; ++i) {
            socialized += _eventAmount(logs[i].data);
        }
    }
}

/// @title EulerLiquidationQuoteMixin
/// @author Phylax Systems
/// @notice Ensures each successful EVK liquidation respects the exact pre-call liquidation quote.
/// @dev Uses call-local input and event data plus `checkLiquidation()` at the pre-call fork, so
///      liquidations inside EVC batches are checked against the state immediately before liquidation.
abstract contract EulerLiquidationQuoteMixin is EulerEVaultBase {
    struct LiquidationInput {
        address violator;
        address collateral;
        uint256 requestedRepay;
        uint256 minYieldBalance;
    }

    struct LiquidationEventData {
        bool found;
        address liquidator;
        address violator;
        address collateral;
        uint256 repayAssets;
        uint256 yieldBalance;
    }

    function _registerLiquidationQuote() internal view {
        registerFnCallTrigger(this.assertLiquidationMatchesPreCallQuote.selector, IEulerEVaultLike.liquidate.selector);
    }

    /// @notice Checks a successful EVK `liquidate` call against its pre-call quote and slippage guard.
    /// @dev A failure means the emitted liquidation result exceeded `checkLiquidation()` from the
    ///      pre-call fork, mismatched calldata, or ignored `minYieldBalance`.
    function assertLiquidationMatchesPreCallQuote() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _assertLiquidationCall(_vault(), ctx.callStart);
    }

    function _assertLiquidationCall(address vault, uint256 callId) internal view {
        LiquidationInput memory input = _liquidationInput(callId);
        LiquidationEventData memory eventData = _liquidateEventForCall(vault, callId);

        require(eventData.found, "EulerEVault: missing Liquidate event");
        require(eventData.violator == input.violator, "EulerEVault: Liquidate violator mismatch");
        require(eventData.collateral == input.collateral, "EulerEVault: Liquidate collateral mismatch");

        _assertLiquidationWithinQuote(vault, callId, input, eventData);
    }

    function _liquidationInput(uint256 callId) internal view returns (LiquidationInput memory inputData) {
        bytes memory input = ph.callinputAt(callId);
        (inputData.violator, inputData.collateral, inputData.requestedRepay, inputData.minYieldBalance) =
            abi.decode(_stripSelector(input), (address, address, uint256, uint256));
    }

    function _assertLiquidationWithinQuote(
        address vault,
        uint256 callId,
        LiquidationInput memory inputData,
        LiquidationEventData memory eventData
    ) internal view {
        (uint256 maxRepay, uint256 maxYield) = abi.decode(
            _viewAt(
                vault,
                abi.encodeCall(
                    IEulerEVaultLike.checkLiquidation, (eventData.liquidator, inputData.violator, inputData.collateral)
                ),
                _preCall(callId)
            ),
            (uint256, uint256)
        );

        require(eventData.repayAssets <= maxRepay, "EulerEVault: liquidation repaid above pre-call quote");
        require(eventData.yieldBalance <= maxYield, "EulerEVault: liquidation yielded above pre-call quote");
        require(eventData.yieldBalance >= inputData.minYieldBalance, "EulerEVault: liquidation ignored min yield");

        if (inputData.requestedRepay != type(uint256).max) {
            require(eventData.repayAssets == inputData.requestedRepay, "EulerEVault: liquidation repay != requested");
        }
    }

    function _liquidateEventForCall(address vault, uint256 callId)
        internal
        view
        returns (LiquidationEventData memory eventData)
    {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: LIQUIDATE_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);
        require(logs.length <= 1, "EulerEVault: multiple Liquidate events");
        if (logs.length == 0) {
            return eventData;
        }

        PhEvm.Log memory log = logs[0];
        require(log.topics.length >= 3, "EulerEVault: malformed Liquidate topics");
        eventData.found = true;
        eventData.liquidator = _topicAddress(log.topics[1]);
        eventData.violator = _topicAddress(log.topics[2]);
        (eventData.collateral, eventData.repayAssets, eventData.yieldBalance) =
            abi.decode(log.data, (address, uint256, uint256));
    }
}

/// @title EulerSmartInflowCircuitBreakerMixin
/// @author Phylax Systems
/// @notice Blocks EVK supply-entry paths when underlying inflow breaches a rolling cap.
/// @dev The executor tracks cumulative inflow for `inflowAsset`. When the cap is tripped,
///      this smart breaker blocks deposit, mint, and skim while leaving stabilizing operations
///      such as repay, liquidation, and touch available.
abstract contract EulerSmartInflowCircuitBreakerMixin is EulerEVaultBase {
    address public immutable inflowAsset;
    uint256 public immutable inflowThresholdBps;
    uint256 public immutable inflowWindowDuration;

    constructor(address asset_, uint256 thresholdBps_, uint256 windowDuration_) {
        inflowAsset = asset_;
        inflowThresholdBps = thresholdBps_;
        inflowWindowDuration = windowDuration_;
    }

    function _registerInflowBreaker() internal view {
        watchCumulativeInflow(
            inflowAsset, inflowThresholdBps, inflowWindowDuration, this.assertNoSupplyEntryDuringInflowBreaker.selector
        );
    }

    /// @notice Ensures a tripped inflow breaker does not include successful EVK supply-entry calls.
    /// @dev A failure identifies a successful supply expansion path in the same transaction
    ///      after the configured cumulative inflow threshold has been breached.
    function assertNoSupplyEntryDuringInflowBreaker() external view {
        address vault = _vault();
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ctx.token == inflowAsset, "EulerEVault: wrong inflow token context");

        require(_matchingCalls(vault, IEulerEVaultLike.deposit.selector, 1).length == 0, "EulerEVault: deposit blocked");
        require(_matchingCalls(vault, IEulerEVaultLike.mint.selector, 1).length == 0, "EulerEVault: mint blocked");
        require(_matchingCalls(vault, IEulerEVaultLike.skim.selector, 1).length == 0, "EulerEVault: skim blocked");
    }
}

/// @title EulerSmartOutflowCircuitBreakerMixin
/// @author Phylax Systems
/// @notice Blocks EVK risk-increasing outflow paths when underlying outflow breaches a rolling cap.
/// @dev The executor tracks cumulative outflow for `outflowAsset`. When the cap is tripped,
///      this smart breaker blocks borrow, withdraw, redeem, flash-loan, and skim paths while
///      leaving stabilizing operations such as deposit, repay, and touch available.
abstract contract EulerSmartOutflowCircuitBreakerMixin is EulerEVaultBase {
    address public immutable outflowAsset;
    uint256 public immutable outflowThresholdBps;
    uint256 public immutable outflowWindowDuration;

    constructor(address asset_, uint256 thresholdBps_, uint256 windowDuration_) {
        outflowAsset = asset_;
        outflowThresholdBps = thresholdBps_;
        outflowWindowDuration = windowDuration_;
    }

    function _registerOutflowBreaker() internal view {
        watchCumulativeOutflow(
            outflowAsset,
            outflowThresholdBps,
            outflowWindowDuration,
            this.assertNoRiskIncreasingOutflowDuringBreaker.selector
        );
    }

    /// @notice Ensures a tripped outflow breaker does not include successful EVK risk-increasing calls.
    /// @dev A failure identifies a successful borrower or asset-exit path in the same transaction
    ///      after the configured cumulative outflow threshold has been breached.
    function assertNoRiskIncreasingOutflowDuringBreaker() external view {
        address vault = _vault();
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == outflowAsset, "EulerEVault: wrong outflow token context");

        require(
            _matchingCalls(vault, IEulerEVaultLike.withdraw.selector, 1).length == 0, "EulerEVault: withdraw blocked"
        );
        require(_matchingCalls(vault, IEulerEVaultLike.redeem.selector, 1).length == 0, "EulerEVault: redeem blocked");
        require(_matchingCalls(vault, IEulerEVaultLike.borrow.selector, 1).length == 0, "EulerEVault: borrow blocked");
        require(
            _matchingCalls(vault, IEulerEVaultLike.flashLoan.selector, 1).length == 0, "EulerEVault: flashLoan blocked"
        );
        require(_matchingCalls(vault, IEulerEVaultLike.skim.selector, 1).length == 0, "EulerEVault: skim blocked");
    }
}

/// @title EulerLayeredOutflowCircuitBreakerMixin
/// @author Phylax Systems
/// @notice Applies EVK outflow response tiers: liquidation-only at 10%, full pause at 15% in 24h.
/// @dev Both tiers use the same underlying asset balance-delta trigger. Above 10% cumulative
///      outflow, a transaction must include a successful liquidation. Above 15% cumulative outflow in 24h,
///      every transaction that still breaches the outflow window reverts.
abstract contract EulerLayeredOutflowCircuitBreakerMixin is EulerEVaultBase {
    uint256 public constant LIQUIDATION_ONLY_OUTFLOW_THRESHOLD_BPS = 1_000;
    uint256 public constant FULL_PAUSE_OUTFLOW_THRESHOLD_BPS = 1_500;
    uint256 public constant OUTFLOW_PAUSE_WINDOW_DURATION = 24 hours;

    address public immutable layeredOutflowAsset;

    constructor(address asset_) {
        layeredOutflowAsset = asset_;
    }

    function _registerLayeredOutflowBreakers() internal view {
        watchCumulativeOutflow(
            layeredOutflowAsset,
            LIQUIDATION_ONLY_OUTFLOW_THRESHOLD_BPS,
            OUTFLOW_PAUSE_WINDOW_DURATION,
            this.assertLiquidationOnlyAfterLargeOutflow.selector
        );
        watchCumulativeOutflow(
            layeredOutflowAsset,
            FULL_PAUSE_OUTFLOW_THRESHOLD_BPS,
            OUTFLOW_PAUSE_WINDOW_DURATION,
            this.assertPauseAfterCriticalOutflow.selector
        );
    }

    /// @notice Enforces liquidation-only mode after 10% cumulative outflow in the rolling window.
    /// @dev A failure means the transaction breached the 10% outflow tier without a successful
    ///      liquidation call.
    function assertLiquidationOnlyAfterLargeOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == layeredOutflowAsset, "EulerEVault: wrong layered outflow token");

        require(
            _matchingCalls(_vault(), IEulerEVaultLike.liquidate.selector, 1).length != 0,
            "EulerEVault: liquidation required"
        );
    }

    /// @notice Fully pauses the EVault after 15% cumulative outflow in 24 hours.
    /// @dev This hard breaker reverts any transaction that still breaches the critical outflow tier.
    function assertPauseAfterCriticalOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == layeredOutflowAsset, "EulerEVault: wrong critical outflow token");

        revert("EulerEVault: critical outflow pause");
    }
}

/// @title EulerEVaultAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle for Euler Vault Kit EVaults.
/// @dev Covers six EVK-specific properties:
///      - changed user storage stays consistent with direct account views
///      - per-call virtual share price cannot drop except for same-call debt socialization
///      - liquidations stay within the exact pre-call `checkLiquidation()` quote
///      - cumulative underlying inflow blocks supply-entry paths after the threshold trips
///      - cumulative underlying outflow blocks risk-increasing outflow paths after the threshold trips
///      - layered cumulative outflow response: liquidation-only at 10%, full pause at 15% in 24h
contract EulerEVaultAssertion is
    EulerUserStorageAccountingMixin,
    EulerPerCallSharePriceMixin,
    EulerLiquidationQuoteMixin,
    EulerSmartInflowCircuitBreakerMixin,
    EulerSmartOutflowCircuitBreakerMixin,
    EulerLayeredOutflowCircuitBreakerMixin
{
    /// @param asset_ Underlying asset of the EVault adopter, used by the flow watchers.
    /// @param sharePriceToleranceBps_ Maximum tolerated call-level virtual share-price decrease.
    /// @param inflowThresholdBps_ Rolling-window inflow cap as basis points of TVL.
    /// @param inflowWindowDuration_ Rolling-window inflow duration in seconds.
    /// @param outflowThresholdBps_ Rolling-window outflow cap as basis points of TVL.
    /// @param outflowWindowDuration_ Rolling-window outflow duration in seconds.
    constructor(
        address asset_,
        uint256 sharePriceToleranceBps_,
        uint256 inflowThresholdBps_,
        uint256 inflowWindowDuration_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_
    )
        EulerPerCallSharePriceMixin(sharePriceToleranceBps_)
        EulerSmartInflowCircuitBreakerMixin(asset_, inflowThresholdBps_, inflowWindowDuration_)
        EulerSmartOutflowCircuitBreakerMixin(asset_, outflowThresholdBps_, outflowWindowDuration_)
        EulerLayeredOutflowCircuitBreakerMixin(asset_)
    {}

    /// @notice Registers all EVK example assertion triggers.
    /// @dev Intended for factory-scoped installs where the assertion adopter is the concrete EVault.
    function triggers() external view override {
        _registerUserStorageAccounting();
        _registerPerCallSharePrice();
        _registerLiquidationQuote();
        _registerInflowBreaker();
        _registerOutflowBreaker();
        _registerLayeredOutflowBreakers();
    }
}

/// @title EulerUserStorageAccountingAssertion
/// @author Phylax Systems
/// @notice Standalone EVK user-storage/account-view consistency assertion for incremental rollout.
contract EulerUserStorageAccountingAssertion is EulerUserStorageAccountingMixin {
    /// @notice Registers the tx-end EVK user storage consistency assertion.
    function triggers() external view override {
        _registerUserStorageAccounting();
    }
}

/// @title EulerPerCallSharePriceAssertion
/// @author Phylax Systems
/// @notice Standalone EVK per-call virtual share-price assertion for incremental rollout.
contract EulerPerCallSharePriceAssertion is EulerPerCallSharePriceMixin {
    constructor(uint256 sharePriceToleranceBps_) EulerPerCallSharePriceMixin(sharePriceToleranceBps_) {}

    /// @notice Registers EVK call-level share-price triggers.
    function triggers() external view override {
        _registerPerCallSharePrice();
    }
}

/// @title EulerLiquidationQuoteAssertion
/// @author Phylax Systems
/// @notice Standalone EVK liquidation quote assertion for incremental rollout.
contract EulerLiquidationQuoteAssertion is EulerLiquidationQuoteMixin {
    /// @notice Registers EVK liquidation quote triggers.
    function triggers() external view override {
        _registerLiquidationQuote();
    }
}

/// @title EulerSmartInflowCircuitBreakerAssertion
/// @author Phylax Systems
/// @notice Standalone EVK smart inflow circuit breaker for incremental rollout.
contract EulerSmartInflowCircuitBreakerAssertion is EulerSmartInflowCircuitBreakerMixin {
    constructor(address asset_, uint256 thresholdBps_, uint256 windowDuration_)
        EulerSmartInflowCircuitBreakerMixin(asset_, thresholdBps_, windowDuration_)
    {}

    /// @notice Registers the EVK cumulative-inflow breaker trigger.
    function triggers() external view override {
        _registerInflowBreaker();
    }
}

/// @title EulerSmartOutflowCircuitBreakerAssertion
/// @author Phylax Systems
/// @notice Standalone EVK smart outflow circuit breaker for incremental rollout.
contract EulerSmartOutflowCircuitBreakerAssertion is EulerSmartOutflowCircuitBreakerMixin {
    constructor(address asset_, uint256 thresholdBps_, uint256 windowDuration_)
        EulerSmartOutflowCircuitBreakerMixin(asset_, thresholdBps_, windowDuration_)
    {}

    /// @notice Registers the EVK cumulative-outflow breaker trigger.
    function triggers() external view override {
        _registerOutflowBreaker();
    }
}

/// @title EulerLayeredOutflowCircuitBreakerAssertion
/// @author Phylax Systems
/// @notice Standalone EVK outflow breaker with liquidation-only and hard-pause response tiers.
contract EulerLayeredOutflowCircuitBreakerAssertion is EulerLayeredOutflowCircuitBreakerMixin {
    constructor(address asset_) EulerLayeredOutflowCircuitBreakerMixin(asset_) {}

    /// @notice Registers the 10% liquidation-only and 15%/24h full-pause outflow triggers.
    function triggers() external view override {
        _registerLayeredOutflowBreakers();
    }
}
