// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "../../../SpecRecorder.sol";

import {CowSettlementHelpers} from "./CowSettlementHelpers.sol";

/// @title CowSettlementAssertion
/// @author Phylax Systems
/// @notice Guards watched Settlement buffers against outflows not explained by GPv2 trade volume
///         or an authorized DAO sweep.
/// @dev A signed order may legitimately pay any receiver, and Trade events do not expose that
///      receiver. The assertion therefore makes no receiver-level claim about normal settlement
///      volume. The two allowances are kept disjoint by destination: transfers to the sweep Safe
///      are always an authorized destination, while outflow to anyone else must be covered by the
///      token's reported trade volume. Because a Safe-bound transfer may itself be an order
///      payment, a transaction that pays both destinations more than trade volume explains cannot
///      be attributed and is explicitly quarantined rather than credited both allowances. Gross
///      accounting catches standing-allowance drains even when same-transaction prefunding hides
///      the endpoint delta.
contract CowSettlementAssertion is CowSettlementHelpers {
    constructor(
        address settlement_,
        address sweepRecipient_,
        address[] memory bufferTokens_,
        uint256 bufferToleranceBps_
    ) CowSettlementHelpers(settlement_, sweepRecipient_, bufferTokens_, bufferToleranceBps_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the per-token outflow reconciliation at transaction end and on token changes.
    function triggers() external view override {
        registerTxEndTrigger(this.assertBufferConserved.selector);
        for (uint256 i; i < bufferTokens.length; ++i) {
            registerErc20ChangeTrigger(this.assertBufferConserved.selector, bufferTokens[i]);
        }
    }

    /// @notice Watched-token outflow must be explained by same-token trade volume or a DAO sweep.
    function assertBufferConserved() external view {
        _requireSettlementIsAdopter();

        for (uint256 i; i < bufferTokens.length; ++i) {
            address token = bufferTokens[i];
            uint256 grossOut = _transferredValueFrom(token, SETTLEMENT);
            uint256 toSafe = _transferredValueAt(token, SETTLEMENT, SWEEP_RECIPIENT, _postTx());
            uint256 toOthers = grossOut - toSafe;
            if (toOthers == 0) {
                // Whether sweep or trade payment, everything landed on the DAO Safe.
                continue;
            }

            uint256 settlementVolume = _reportedTradeVolume(token);
            require(toOthers <= settlementVolume, "CowSettlement: external buffer drain");
            // A Safe-bound transfer may be either a DAO sweep or a trade payment, and Trade
            // events do not identify receivers, so once both destinations see outflow the volume
            // allowance cannot be attributed between them: crediting both would let a trade that
            // pays the Safe authorize an equal-sized drain. Accept only when trade volume alone
            // explains every outflow and quarantine the ambiguous remainder.
            require(grossOut <= settlementVolume, "CowSettlement: unattributable sweep and trade outflow");
        }
    }
}
