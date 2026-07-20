// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {IGPv2SettlementLike} from "./CowSettlementInterfaces.sol";

/// @title CowSettlementHelpers
/// @author Phylax Systems
/// @notice Fork-aware, log-aware helpers for the CoW Protocol (GPv2) settlement assertions.
/// @dev The assertion adopter is the `GPv2Settlement` contract. These helpers wire up the bundle's
///      immutable configuration and provide the two observations the invariants need:
///      - the solver that authored a settlement call (the call's caller), and
///      - the value the settlement contract moves out to a given recipient (via Transfer logs and
///        ERC20 balance deltas).
///      All reads go through snapshot forks / call-scoped logs; the bundle keeps no assertion-owned
///      state of its own.
abstract contract CowSettlementHelpers is Assertion {
    /// @notice The GPv2 settlement contract this bundle protects (the assertion adopter).
    address internal immutable SETTLEMENT;

    /// @notice The single authorized destination for buffer outflows (the CoW DAO reward/sweep
    ///         Safe). Net reductions of the settlement's buffer are only allowed when they land here.
    address internal immutable SWEEP_RECIPIENT;

    /// @notice The buffer tokens whose settlement-held balances are protected (e.g. fee tokens that
    ///         accumulate between DAO sweeps, such as the DAI buffer drained in the 2023 incident).
    address[] internal bufferTokens;

    /// @dev Configuration is passed in explicitly; the constructor never reads adopter state, since
    ///      the assertion-deploy runtime is isolated from the calling state.
    constructor(
        address settlement_,
        address sweepRecipient_,
        address[] memory bufferTokens_,
        uint256 bufferToleranceBps_
    ) {
        require(settlement_ != address(0), "CowSettlement: settlement zero");
        require(sweepRecipient_ != address(0), "CowSettlement: sweep recipient zero");
        require(bufferToleranceBps_ == 0, "CowSettlement: external drain tolerance must be zero");
        SETTLEMENT = settlement_;
        SWEEP_RECIPIENT = sweepRecipient_;

        for (uint256 i; i < bufferTokens_.length; ++i) {
            require(bufferTokens_[i] != address(0), "CowSettlement: buffer token zero");
            for (uint256 j; j < i; ++j) {
                require(bufferTokens_[j] != bufferTokens_[i], "CowSettlement: duplicate buffer token");
            }
            bufferTokens.push(bufferTokens_[i]);
        }
    }

    /// @notice Reverts unless the configured settlement is the adopter for the current transaction.
    function _requireSettlementIsAdopter() internal view {
        require(ph.getAssertionAdopter() == SETTLEMENT, "CowSettlement: configured settlement is not adopter");
    }

    function _settlementExecutionOccurred() internal view returns (bool) {
        return ph.getCallInputs(SETTLEMENT, IGPv2SettlementLike.settle.selector).length != 0
            || ph.getCallInputs(SETTLEMENT, IGPv2SettlementLike.swap.selector).length != 0;
    }
}
