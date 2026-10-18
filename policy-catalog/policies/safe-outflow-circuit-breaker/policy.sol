// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title SafeOutflowCircuitBreakerAssertion
/// @notice Caps how much of one token can leave a Safe in a rolling window, at a limit fitted
///         to the Safe's own history.
/// @dev Adopted by a Safe, one instance per (token, window). The action policy decides how
///      funds may leave; this decides how fast. It counts every way the Safe's balance can fall: a
///      Safe transaction, a batch, or a `transferFrom` pull by a contract the Safe approved, even in a
///      transaction the Safe never signed.
///      - The window counter is the Safe's net outflow of the token (out minus in) over the last
///        `WINDOW` seconds, kept by the executor. The trigger threshold is 1 bps of the window-start
///        balance, so the absolute `LIMIT` is what decides.
///      - Once the counter reaches `LIMIT`, any transaction that moves the token out of the Safe is
///        rejected until the window rolls forward. Inflows always pass.
///      - Transfers to other Safes count like any other. Inflows offset the counter, so an
///        exemption for them would let funds pass through: a Safe could receive a sibling's balance
///        and send it on with its counter near zero. Without one, a drain through any chain of Derive
///        Safes is bounded by the sum of their limits per window. Sweeps larger than a limit are
///        planned one-offs: disable, sweep, re-enable.
///      - Burns (a LayerZero OFT `send`) count: the tokens leave the Safe's custody.
contract SafeOutflowCircuitBreakerAssertion is Assertion {
    /// @notice The ERC-20 this instance watches.
    address public immutable TOKEN;
    /// @notice Rolling window length in seconds.
    uint256 public immutable WINDOW;
    /// @notice Net outflow over the window, in token units, at which outflows stop.
    uint256 public immutable LIMIT;

    constructor(address token, uint256 window, uint256 limit) {
        require(token != address(0), "Safe breaker: token zero");
        require(window >= 10 && window <= type(uint64).max, "Safe breaker: invalid window");
        require(limit != 0, "Safe breaker: limit zero");
        TOKEN = token;
        WINDOW = window;
        LIMIT = limit;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view virtual override {
        watchCumulativeOutflow(TOKEN, 1, WINDOW, this.assertionOutflowWithinLimit.selector);
    }

    /// @notice While the window's net outflow is at or above `LIMIT`, the token cannot leave the Safe.
    /// - The counter includes this transaction, so the transaction that reaches the limit is rejected.
    /// - A failure means the Safe tried to pay out more of the token, in the window, than its history
    ///   supports.
    function assertionOutflowWithinLimit() external view {
        if (_windowOutflow() < LIMIT) return;
        address safe = ph.getAssertionAdopter();
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == safe && transfers[i].to != safe && transfers[i].value != 0) {
                revert("Safe: outflow limit reached");
            }
        }
    }

    /// @dev The executor's net outflow for the window, including this transaction.
    function _windowOutflow() internal view virtual returns (uint256) {
        return ph.outflowContext().cumulativeOutflow;
    }
}
