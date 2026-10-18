// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title TokenOutflowCircuitBreakerAssertion
/// @notice A constructor-configured rolling token outflow limit for any custody adopter.
/// @dev Generalizes the independent Derive SpotVault breaker and Lighter bridge breaker. The
///      executor maintains the rolling net-outflow context; this assertion decides whether an
///      armed transaction is a hard stop when transactionCapBps is zero, or a soft per-transaction cap.
///      Deploy one instance per token and threshold tier. minimumOutflow is zero when the
///      adopter does not need Derive's thin-asset floor.
contract TokenOutflowCircuitBreakerAssertion is Assertion {
    address public immutable TOKEN;
    uint256 public immutable THRESHOLD_BPS;
    uint256 public immutable WINDOW;
    uint256 public immutable MINIMUM_OUTFLOW;
    uint256 public immutable TRANSACTION_CAP_BPS;

    constructor(
        address token_,
        uint256 thresholdBps_,
        uint256 window_,
        uint256 minimumOutflow_,
        uint256 transactionCapBps_
    ) {
        require(token_ != address(0), "Outflow breaker: token zero");
        require(thresholdBps_ > 0 && thresholdBps_ < 10_000, "Outflow breaker: invalid threshold");
        require(window_ >= 10 && window_ <= type(uint64).max, "Outflow breaker: invalid window");
        require(transactionCapBps_ < thresholdBps_, "Outflow breaker: cap must be below threshold");
        TOKEN = token_;
        THRESHOLD_BPS = thresholdBps_;
        WINDOW = window_;
        MINIMUM_OUTFLOW = minimumOutflow_;
        TRANSACTION_CAP_BPS = transactionCapBps_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        watchCumulativeOutflow(TOKEN, THRESHOLD_BPS, WINDOW, this.assertionOutflowWithinLimit.selector);
    }

    function assertionOutflowWithinLimit() external view {
        PhEvm.OutflowContext memory context = ph.outflowContext();
        if (context.cumulativeOutflow < MINIMUM_OUTFLOW) return;

        address adopter = ph.getAssertionAdopter();
        uint256 grossOutflow;
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == adopter && transfers[i].to != adopter) grossOutflow += transfers[i].value;
        }
        if (grossOutflow == 0) return;
        if (TRANSACTION_CAP_BPS == 0) revert("Outflow breaker: hard limit reached");

        uint256 balance = _readBalanceAt(TOKEN, adopter, _preTx());
        if (context.tvlSnapshot != 0 && context.tvlSnapshot < balance) balance = context.tvlSnapshot;
        require(grossOutflow * 10_000 <= balance * TRANSACTION_CAP_BPS, "Outflow breaker: transaction cap exceeded");
    }
}
