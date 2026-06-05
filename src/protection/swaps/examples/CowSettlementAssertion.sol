// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {CowSettlementHelpers} from "./CowSettlementHelpers.sol";
import {IGPv2SettlementLike} from "./CowSettlementInterfaces.sol";

/// @title CowSettlementAssertion
/// @author Phylax Systems
/// @notice Example assertion bundle protecting a CoW Protocol (Gnosis Protocol v2) settlement
///         contract against the two on-chain harms a malicious (or compromised) solver can cause
///         that the settlement contract does NOT guard against itself.
/// @dev The GPv2 settlement contract gates `settle`/`swap` behind an allowlist of bonded solvers,
///      enforces user signatures, limit prices, fill amounts and expiry, and forbids interactions
///      with the vault relayer. What it intentionally leaves open — solvers may run arbitrary
///      interactions and may dip into the contract's own accumulated buffers — is exactly what these
///      two invariants cover. Neither uses a price oracle; both observe real token movements.
///
///      1. Surplus protection (`assertSolverDoesNotExtractValue`, per `settle`/`swap` call):
///         the settlement contract must not pay any of its tokens to the solver that authored the
///         call. Solver rewards are paid out-of-band in COW; a settlement that transfers tokens to
///         its own caller is siphoning batch surplus / buffer value that belongs to users or the DAO.
///
///      2. Inventory protection (`assertBufferConserved`, per watched-token balance change):
///         the settlement contract's accumulated buffer for each watched token must not be net
///         reduced across the transaction, unless the entire reduction is explained by transfers to
///         the authorized DAO sweep recipient. This catches buffer drains regardless of mechanism —
///         including the standing-approval class of drain behind the February 2023 incident, where a
///         solver helper held a max approval on the settlement's DAI buffer.
///
///      Limitations (documented intentionally, not bugs): without a reference price the bundle
///      cannot judge whether surplus was "fairly" maximized, only that it did not flow to the
///      solver; and the surplus check assumes the solver address is not itself an order receiver in
///      the same batch.
contract CowSettlementAssertion is CowSettlementHelpers {
    constructor(
        address settlement_,
        address sweepRecipient_,
        address[] memory bufferTokens_,
        uint256 bufferToleranceBps_
    ) CowSettlementHelpers(settlement_, sweepRecipient_, bufferTokens_, bufferToleranceBps_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the surplus check against the solver-only entry points, and the buffer
    ///         conservation check at transaction end.
    /// @dev The surplus check is call-scoped (it needs the per-call solver and the call's Transfer
    ///      logs). The buffer check is a transaction-envelope property (PreTx vs PostTx custody), so
    ///      it is registered at tx end. PRODUCTION HARDENING: also register
    ///      `registerErc20ChangeTrigger(this.assertBufferConserved.selector, bufferTokens[i])` per
    ///      token so the buffer check fires even for a drain transaction that never calls the
    ///      settlement contract directly — the standing-approval class behind the Feb-2023 incident,
    ///      where an external helper held a max approval on the settlement's DAI buffer.
    function triggers() external view override {
        registerFnCallTrigger(this.assertSolverDoesNotExtractValue.selector, IGPv2SettlementLike.settle.selector);
        registerFnCallTrigger(this.assertSolverDoesNotExtractValue.selector, IGPv2SettlementLike.swap.selector);

        registerTxEndTrigger(this.assertBufferConserved.selector);
    }

    /// @notice A settlement must not pay batch surplus to the solver that authored it.
    /// @dev Solvers are compensated off-chain in COW, never by the settlement contract transferring
    ///      traded tokens back to its own caller. Any token (across the whole call frame, including
    ///      nested solver interactions) moved from the settlement contract to the solver is treated
    ///      as siphoned surplus / buffer value and trips the assertion. A failure means the solver
    ///      directed value that should have reached users (as price improvement) or stayed in the
    ///      DAO buffer to itself instead. This is the on-chain footprint of surplus theft that the
    ///      settlement's signature / limit-price checks cannot catch, because those only guarantee
    ///      the user's signed floor, not where any excess goes.
    function assertSolverDoesNotExtractValue() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireSettlementIsAdopter();

        address solver = _solver();
        uint256 extracted = _valueFromSettlementTo(ctx.callStart, solver);

        require(extracted == 0, "CowSettlement: solver extracted value from settlement");
    }

    /// @notice The settlement contract's buffer for each watched token must not be net-drained
    ///         except by an authorized DAO sweep.
    /// @dev Compares the settlement's balance at PreTx and PostTx for every watched token. A buffer
    ///      that grows or holds is always fine (fees and positive slippage accrue there). A net
    ///      reduction is only allowed when the full amount (minus a small dust tolerance) is
    ///      transferred to the configured sweep recipient. Any other net outflow — a solver routing
    ///      the buffer to itself, or an external contract exploiting a standing approval on the
    ///      settlement's balance — trips the assertion. The ERC20-change trigger means this fires
    ///      even for a drain transaction that never calls the settlement contract directly.
    function assertBufferConserved() external view {
        _requireSettlementIsAdopter();

        for (uint256 i; i < bufferTokens.length; ++i) {
            address token = bufferTokens[i];

            uint256 pre = _readBalanceAt(token, SETTLEMENT, _preTx());
            uint256 post = _readBalanceAt(token, SETTLEMENT, _postTx());
            if (post >= pre) {
                continue;
            }

            uint256 netOut = pre - post;
            uint256 swept = _transferredValueAt(token, SETTLEMENT, SWEEP_RECIPIENT, _postTx());
            uint256 tolerance = (pre * BUFFER_TOLERANCE_BPS) / BPS;

            require(netOut <= swept + tolerance, "CowSettlement: buffer drained to unauthorized recipient");
        }
    }
}
