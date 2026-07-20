// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "../../../SpecRecorder.sol";

import {CowSettlementHelpers} from "./CowSettlementHelpers.sol";

/// @title CowSettlementAssertion
/// @author Phylax Systems
/// @notice Narrow guard for watched Settlement buffers outside normal GPv2 execution.
/// @dev A signed order may legitimately pay the solver, and Trade volume cannot authorize a
///      particular recipient. This bundle therefore makes no receiver-level claim about a normal
///      `settle` or `swap`. It only rejects a watched-token balance reduction in a transaction with
///      no successful Settlement execution unless the reduction went to the configured sweep Safe.
///      This covers the standing-allowance drain shape without inventing GPv2 settlement semantics.
contract CowSettlementAssertion is CowSettlementHelpers {
    constructor(
        address settlement_,
        address sweepRecipient_,
        address[] memory bufferTokens_,
        uint256 bufferToleranceBps_
    ) CowSettlementHelpers(settlement_, sweepRecipient_, bufferTokens_, bufferToleranceBps_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Registers the narrow external-drain check at transaction end and on token changes.
    function triggers() external view override {
        registerTxEndTrigger(this.assertBufferConserved.selector);
        for (uint256 i; i < bufferTokens.length; ++i) {
            registerErc20ChangeTrigger(this.assertBufferConserved.selector, bufferTokens[i]);
        }
    }

    /// @notice Outside `settle`/`swap`, watched balance reductions must go to the sweep Safe.
    function assertBufferConserved() external view {
        _requireSettlementIsAdopter();

        for (uint256 i; i < bufferTokens.length; ++i) {
            address token = bufferTokens[i];

            uint256 pre = _readBalanceAt(token, SETTLEMENT, _preTx());
            uint256 post = _readBalanceAt(token, SETTLEMENT, _postTx());
            if (post >= pre || _settlementExecutionOccurred()) {
                continue;
            }

            uint256 netOut = pre - post;
            uint256 swept = _transferredValueAt(token, SETTLEMENT, SWEEP_RECIPIENT, _postTx());
            require(swept >= netOut, "CowSettlement: external buffer drain");
        }
    }
}
