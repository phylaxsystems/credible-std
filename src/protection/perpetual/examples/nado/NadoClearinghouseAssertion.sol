// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "../../../../SpecRecorder.sol";
import {PhEvm} from "../../../../PhEvm.sol";

import {NadoHelpers} from "./NadoHelpers.sol";
import {INadoClearinghouseLike, INadoEndpointLike} from "./NadoInterfaces.sol";

/// @title NadoClearinghouseAssertion
/// @author Phylax Systems
/// @notice Protects the Nado clearinghouse custody and collateral-accounting boundary.
/// @dev The bundle intentionally focuses on a small set of high-signal checks:
///      - successful Clearinghouse deposits must credit SpotEngine collateral by the scaled token amount
///      - successful Clearinghouse withdrawals must debit SpotEngine collateral and move exactly the native token amount
///      - quote-asset flow circuit breakers override protocol-level limits during abnormal daily flow windows
contract NadoClearinghouseAssertion is NadoHelpers {
    uint256 public immutable quoteInflowPauseThresholdBps;
    uint256 public immutable quoteOutflowWithdrawalOnlyThresholdBps;
    uint256 public immutable quoteOutflowPauseThresholdBps;
    uint256 public immutable flowWindowDuration;

    constructor(
        address endpoint_,
        address clearinghouse_,
        address spotEngine_,
        address quoteAsset_,
        address withdrawPool_,
        uint256 collateralDeltaToleranceX18_,
        uint256 quoteInflowPauseThresholdBps_,
        uint256 quoteOutflowWithdrawalOnlyThresholdBps_,
        uint256 quoteOutflowPauseThresholdBps_,
        uint256 flowWindowDuration_
    ) NadoHelpers(endpoint_, clearinghouse_, spotEngine_, quoteAsset_, withdrawPool_, collateralDeltaToleranceX18_) {
        registerAssertionSpec(AssertionSpec.Reshiram);

        quoteInflowPauseThresholdBps = quoteInflowPauseThresholdBps_;
        quoteOutflowWithdrawalOnlyThresholdBps = quoteOutflowWithdrawalOnlyThresholdBps_;
        quoteOutflowPauseThresholdBps = quoteOutflowPauseThresholdBps_;
        flowWindowDuration = flowWindowDuration_;
    }

    /// @notice Registers Nado collateral-accounting checks and quote-asset flow breakers.
    function triggers() external view override {
        registerFnCallTrigger(
            this.assertDepositCreditsSpotBalance.selector, INadoClearinghouseLike.depositCollateral.selector
        );
        registerFnCallTrigger(
            this.assertWithdrawalDebitsSpotBalance.selector, INadoClearinghouseLike.withdrawCollateral.selector
        );
        registerFnCallTrigger(
            this.assertRebalanceXWithdrawDebitsSpotBalance.selector, INadoClearinghouseLike.rebalanceXWithdraw.selector
        );

        watchCumulativeInflow(
            quoteAsset, quoteInflowPauseThresholdBps, flowWindowDuration, this.assertQuoteInflowPaused.selector
        );
        watchCumulativeOutflow(
            quoteAsset,
            quoteOutflowWithdrawalOnlyThresholdBps,
            flowWindowDuration,
            this.assertQuoteOutflowIsWithdrawalPath.selector
        );
        watchCumulativeOutflow(
            quoteAsset, quoteOutflowPauseThresholdBps, flowWindowDuration, this.assertQuoteOutflowPaused.selector
        );
    }

    /// @notice Checks that a successful `Clearinghouse.depositCollateral` credits the sender's spot balance.
    /// @dev A failure means the custody-to-ledger conversion credited too little, too much, or the wrong product.
    function assertDepositCreditsSpotBalance() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        INadoClearinghouseLike.DepositCollateral memory txn =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (INadoClearinghouseLike.DepositCollateral));

        address productToken = _productTokenAt(txn.productId, afterFork);
        uint8 decimals = _tokenDecimalsAt(productToken, afterFork);
        int256 expectedDelta = _realizedAmountX18(txn.amount, decimals);
        int256 actualDelta = int256(_spotBalanceAt(txn.productId, txn.sender, afterFork))
            - int256(_spotBalanceAt(txn.productId, txn.sender, beforeFork));

        _assertApproxEq(actualDelta, expectedDelta, collateralDeltaToleranceX18, "Nado: deposit spot credit mismatch");
    }

    /// @notice Checks that `Clearinghouse.withdrawCollateral` debits spot balance and releases exact custody.
    /// @dev A failure means a withdrawal produced an accounting debit/token outflow mismatch.
    function assertWithdrawalDebitsSpotBalance() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        (bytes32 sender, uint32 productId, uint128 amount,,) =
            abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (bytes32, uint32, uint128, address, uint64));

        _assertSpotDebitAndCustodyOutflow(sender, productId, amount, beforeFork, afterFork);
    }

    /// @notice Checks that `rebalanceXWithdraw` debits the X account and releases exact custody.
    /// @dev This covers the public X-account withdrawal path because it calls `withdrawCollateral` internally.
    function assertRebalanceXWithdrawDebitsSpotBalance() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory beforeFork = _preCall(ctx.callStart);
        PhEvm.ForkId memory afterFork = _postCall(ctx.callEnd);
        (bytes memory transaction,) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (bytes, uint64));
        INadoClearinghouseLike.RebalanceXWithdraw memory txn =
            abi.decode(_stripTransactionType(transaction), (INadoClearinghouseLike.RebalanceXWithdraw));

        _assertSpotDebitAndCustodyOutflow(X_ACCOUNT, txn.productId, txn.amount, beforeFork, afterFork);
    }

    function _assertSpotDebitAndCustodyOutflow(
        bytes32 sender,
        uint32 productId,
        uint128 amount,
        PhEvm.ForkId memory beforeFork,
        PhEvm.ForkId memory afterFork
    ) internal view {
        address productToken = _productTokenAt(productId, beforeFork);
        uint8 decimals = _tokenDecimalsAt(productToken, beforeFork);
        int256 expectedDelta = -_realizedAmountX18(amount, decimals);
        int256 actualDelta = int256(_spotBalanceAt(productId, sender, afterFork))
            - int256(_spotBalanceAt(productId, sender, beforeFork));

        _assertApproxEq(actualDelta, expectedDelta, collateralDeltaToleranceX18, "Nado: withdrawal spot debit mismatch");
        _assertTokenDelta(
            _clearinghouseTokenBalanceAt(productToken, beforeFork),
            _clearinghouseTokenBalanceAt(productToken, afterFork),
            amount,
            "Nado: withdrawal custody outflow mismatch"
        );
    }

    /// @notice Hard-pauses the clearinghouse after abnormal quote inflow exceeds the configured window cap.
    /// @dev This is intentionally stricter than protocol min-deposit checks: the breached flow window reverts.
    function assertQuoteInflowPaused() external view {
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ctx.token == quoteAsset, "Nado: wrong quote inflow context");

        revert("Nado: quote inflow circuit breaker");
    }

    /// @notice Allows large quote outflow only when the transaction used an explicit Nado withdrawal path.
    /// @dev A failure means the quote outflow exceeded the warning tier without a clearinghouse withdrawal action.
    function assertQuoteOutflowIsWithdrawalPath() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == quoteAsset, "Nado: wrong quote outflow context");

        require(_hasWithdrawalPathCall(), "Nado: quote outflow requires withdrawal path");
    }

    /// @notice Hard-pauses the clearinghouse after critical quote outflow exceeds the configured window cap.
    /// @dev This overrides the protocol's normal withdrawal and fast-withdrawal limits during severe outflow.
    function assertQuoteOutflowPaused() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == quoteAsset, "Nado: wrong critical quote outflow context");

        revert("Nado: quote outflow circuit breaker");
    }

    function _hasWithdrawalPathCall() internal view returns (bool) {
        return _matchingCalls(clearinghouse, INadoClearinghouseLike.withdrawCollateral.selector, 1).length != 0
            || _matchingCalls(clearinghouse, INadoClearinghouseLike.withdrawInsurance.selector, 1).length != 0
            || _matchingCalls(clearinghouse, INadoClearinghouseLike.rebalanceXWithdraw.selector, 1).length != 0
            || _matchingCalls(endpoint, INadoEndpointLike.submitSlowModeTransaction.selector, 1).length != 0;
    }
}
