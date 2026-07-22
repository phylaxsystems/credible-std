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
///      volume. It instead reconciles each watched token's gross outflow against that token's own
///      reported trade volume or transfers to the configured sweep Safe. Transactions containing
///      both are rejected because a transfer to the Safe cannot be attributed unambiguously and
///      must not consume both allowances. Gross accounting catches standing-allowance drains even
///      when same-transaction prefunding hides the endpoint delta.
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
            uint256 swept = _transferredValueAt(token, SETTLEMENT, SWEEP_RECIPIENT, _postTx());
            uint256 settlementVolume = _reportedTradeVolume(token);

            require(swept == 0 || settlementVolume == 0, "CowSettlement: ambiguous sweep and trade");
            require(grossOut <= swept + settlementVolume, "CowSettlement: external buffer drain");
        }
    }
}
