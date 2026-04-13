// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Credible} from "../../Credible.sol";
import {PhEvm} from "../../PhEvm.sol";
import {LendingProtectionSuiteAdapter} from "./LendingProtectionSuiteAdapter.sol";

/// @notice Minimal token balance surface used by lending protection helpers.
interface IERC20BalanceReaderLike {
    function balanceOf(address account) external view returns (uint256);
}

/// @title LendingProtectionSuiteBase
/// @author Phylax Systems
/// @notice Shared snapshot-read helpers for lending protection suites.
abstract contract LendingProtectionSuiteBase is Credible, LendingProtectionSuiteAdapter {
    /// @notice Gas forwarded to snapshot-time protocol view calls made through `ph.staticcallAt`.
    /// @dev Suite implementations can rely on this constant for protocol reads that need to execute
    ///      inside a forked snapshot rather than against the live assertion deployment context.
    uint64 internal constant SUITE_VIEW_GAS = 500_000;

    /// @notice Executes a static call against `target` at a specific snapshot fork.
    /// @dev Helper for suite authors implementing `getAccountState(...)`, `getAccountBalances(...)`,
    ///      or custom snapshot logic. Reverts when the underlying protocol read fails so callers do
    ///      not accidentally operate on partially decoded state.
    /// @param target The protocol contract to query.
    /// @param data ABI-encoded calldata for the target view.
    /// @param fork The snapshot fork the read should execute against.
    /// @return resultData Raw return bytes from the static call.
    function _suiteViewAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bytes memory resultData)
    {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(target, data, SUITE_VIEW_GAS, fork);
        require(result.ok, "lending suite staticcall failed");
        return result.data;
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint256`.
    /// @param target The protocol contract to query.
    /// @param data ABI-encoded calldata for the target view.
    /// @param fork The snapshot fork the read should execute against.
    /// @return value The decoded `uint256` result.
    function _suiteReadUintAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (uint256));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint8`.
    /// @param target The protocol contract to query.
    /// @param data ABI-encoded calldata for the target view.
    /// @param fork The snapshot fork the read should execute against.
    /// @return value The decoded `uint8` result.
    function _suiteReadUint8At(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint8 value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (uint8));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `address`.
    /// @param target The protocol contract to query.
    /// @param data ABI-encoded calldata for the target view.
    /// @param fork The snapshot fork the read should execute against.
    /// @return value The decoded `address` result.
    function _suiteReadAddressAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (address value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (address));
    }

    /// @notice Convenience wrapper that reads an ERC20-style `balanceOf(account)` at a snapshot fork.
    /// @dev Useful for claim, debt-token, and collateral-token accounting when an invariant only
    ///      depends on token balances and not on bespoke protocol storage.
    /// @param token The token contract to query.
    /// @param account The account whose balance should be read.
    /// @param fork The snapshot fork the read should execute against.
    /// @return balance The decoded token balance.
    function _suiteReadBalanceAt(address token, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        return _suiteReadUintAt(token, abi.encodeCall(IERC20BalanceReaderLike.balanceOf, (account)), fork);
    }

    /// @notice Returns the raw return bytes for a traced call.
    /// @dev This is helpful for clipped operations whose actual effect is returned directly by the
    ///      protocol entrypoint, such as withdraw functions that return the actual amount withdrawn.
    ///      For on-call assertions this is typically `TriggeredCall.callStart`, not `callEnd`.
    /// @param callId The traced call identifier obtained from `TriggeredCall`.
    /// @return output ABI-encoded return bytes emitted by the traced call.
    function _suiteCallOutputAt(uint256 callId) internal view returns (bytes memory output) {
        return ph.callOutputAt(callId);
    }

    /// @notice Decodes the raw output for a traced call as a single `uint256`.
    /// @dev This is a convenience wrapper for common lending entrypoints whose actual effect is
    ///      returned directly by the protocol, such as `withdraw(...)`.
    /// @param callId The traced call identifier obtained from `TriggeredCall`.
    /// @return value The decoded `uint256` return value.
    function _suiteReadUint256OutputAt(uint256 callId) internal view returns (uint256 value) {
        return abi.decode(_suiteCallOutputAt(callId), (uint256));
    }

    /// @notice Returns reduced ERC20 transfer deltas for a token within the selected fork scope.
    /// @dev This is built on top of `ph.reduceErc20BalanceDeltas(...)` and is useful when suite
    ///      authors need to measure the actual token movement caused by a successful operation.
    /// @param token The ERC20 token whose transfer deltas should be queried.
    /// @param fork The fork whose log scope should be inspected.
    /// @return deltas Aggregated transfer values keyed by `(from, to)` pair.
    function _suiteReducedErc20BalanceDeltasAt(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (PhEvm.Erc20TransferData[] memory deltas)
    {
        return ph.reduceErc20BalanceDeltas(token, fork);
    }

    /// @notice Returns the total amount of `token` transferred from `from` to `to` in the fork scope.
    /// @dev This helper eliminates the most common ERC20-introspection boilerplate for bounded-
    ///      consumption assertions. It sums reduced transfer deltas, so callers can use it directly
    ///      even if the protocol emits multiple transfers between the same accounts.
    /// @param token The ERC20 token whose transfer deltas should be queried.
    /// @param from The expected sender of the token movement.
    /// @param to The expected receiver of the token movement.
    /// @param fork The fork whose log scope should be inspected.
    /// @return value Total token amount transferred from `from` to `to`.
    function _suiteTransferredValueAt(address token, address from, address to, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        PhEvm.Erc20TransferData[] memory deltas = _suiteReducedErc20BalanceDeltasAt(token, fork);

        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == from && deltas[i].to == to) {
                value += deltas[i].value;
            }
        }
    }

    /// @notice Computes the non-negative decrease between two snapshot values.
    /// @dev This saturates at zero when the post-operation value is unchanged or larger. Suite
    ///      authors can use it to express actual consumption without worrying about underflow.
    /// @param beforeValue Resource value observed before the operation.
    /// @param afterValue Resource value observed after the operation.
    /// @return consumed Amount by which the resource decreased across the operation.
    function _consumedBetween(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256 consumed) {
        return beforeValue > afterValue ? beforeValue - afterValue : 0;
    }
}
