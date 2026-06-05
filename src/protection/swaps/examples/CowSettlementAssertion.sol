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
///         the settlement contract's watched-token outflow must be explained by authorized DAO
///         sweeps or by actual GPv2 `Trade` volume emitted by the settlement. This catches buffer
///         drains that are not settlement volume, including the standing-approval class behind the
///         February 2023 incident, while allowing normal settlements to use accumulated inventory.
///
///      Limitations (documented intentionally, not bugs): without a reference price the bundle
///      cannot judge whether surplus was "fairly" maximized, only that it did not flow to the
///      solver; the surplus check assumes the solver address is not itself an order receiver in the
///      same batch; and `Trade` events do not expose receivers, so the buffer check reconciles
///      settlement volume rather than receiver-level authorization.
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
    ///         conservation check at transaction end and on watched-token balance changes.
    /// @dev The surplus check is call-scoped (it needs the per-call solver and the call's Transfer
    ///      logs). The buffer check is a transaction-envelope property, so it runs at tx end and on
    ///      ERC20 balance changes for every watched token. The ERC20-change trigger lets the check
    ///      fire for a drain transaction that never calls the settlement contract directly.
    function triggers() external view override {
        registerFnCallTrigger(this.assertSolverDoesNotExtractValue.selector, IGPv2SettlementLike.settle.selector);
        registerFnCallTrigger(this.assertSolverDoesNotExtractValue.selector, IGPv2SettlementLike.swap.selector);

        registerTxEndTrigger(this.assertBufferConserved.selector);
        for (uint256 i; i < bufferTokens.length; ++i) {
            registerErc20ChangeTrigger(this.assertBufferConserved.selector, bufferTokens[i]);
        }
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

        address solver = _solver(ctx.selector, ctx.callStart);
        uint256 extracted = _valueFromSettlementTo(ctx.callStart, solver);

        require(extracted == 0, "CowSettlement: solver extracted value from settlement");
    }

    /// @notice The settlement contract's watched-token outflow must be explained by GPv2 settlement
    ///         volume or an authorized DAO sweep.
    /// @dev Reconciles both gross ERC20 outflow and net PreTx/PostTx balance decrease for every
    ///      watched token. Normal settlements can legitimately use accumulated inventory, so GPv2
    ///      `Trade` event volume is allowed. Authorized sweeps to the configured recipient are also
    ///      allowed. Any remaining outflow — including an external contract exploiting a standing
    ///      approval on the settlement's balance — trips the assertion.
    function assertBufferConserved() external view {
        _requireSettlementIsAdopter();

        for (uint256 i; i < bufferTokens.length; ++i) {
            address token = bufferTokens[i];

            uint256 pre = _readBalanceAt(token, SETTLEMENT, _preTx());
            uint256 post = _readBalanceAt(token, SETTLEMENT, _postTx());
            uint256 grossOut = _transferredValueFrom(token, SETTLEMENT);
            uint256 swept = _transferredValueAt(token, SETTLEMENT, SWEEP_RECIPIENT, _postTx());
            uint256 settlementVolume = _reportedTradeVolume(token);
            uint256 tolerance = (pre * BUFFER_TOLERANCE_BPS) / BPS;
            uint256 allowedOut = _saturatingAdd(_saturatingAdd(swept, settlementVolume), tolerance);

            require(grossOut <= allowedOut, "CowSettlement: buffer moved to unauthorized recipient");

            if (post < pre) {
                uint256 netOut = pre - post;
                require(netOut <= allowedOut, "CowSettlement: buffer drained to unauthorized recipient");
            }
        }
    }
}
