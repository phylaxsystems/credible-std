// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";

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
    /// @dev keccak256("Trade(address,address,address,uint256,uint256,uint256,bytes)") from GPv2Settlement.
    bytes32 internal constant GPV2_TRADE_TOPIC =
        keccak256("Trade(address,address,address,uint256,uint256,uint256,bytes)");

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

    /// @notice Returns token volume that GPv2 itself reported as executed for the watched token.
    /// @dev Sums both sell and buy legs from GPv2 `Trade` events. The event does not identify the
    ///      receiver, so this is a per-token volume allowance rather than recipient authorization.
    function _reportedTradeVolume(address token) internal view returns (uint256 volume) {
        PhEvm.Log[] memory logs =
            ph.getLogsQuery(PhEvm.LogQuery({emitter: SETTLEMENT, signature: GPV2_TRADE_TOPIC}), _postTx());

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].data.length < 192) {
                continue;
            }

            (address sellToken, address buyToken, uint256 sellAmount, uint256 buyAmount,,) =
                abi.decode(logs[i].data, (address, address, uint256, uint256, uint256, bytes));

            if (sellToken == token) {
                volume += sellAmount;
            }
            if (buyToken == token) {
                volume += buyAmount;
            }
        }
    }

    /// @notice Returns total standard ERC20 outflow from `from` for one token over the transaction.
    function _transferredValueFrom(address token, address from) internal view returns (uint256 value) {
        PhEvm.Erc20TransferData[] memory deltas = _reducedErc20BalanceDeltasAt(token, _postTx());

        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == from) {
                value += deltas[i].value;
            }
        }
    }
}
