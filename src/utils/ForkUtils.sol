// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Credible} from "../Credible.sol";
import {PhEvm} from "../PhEvm.sol";

/// @notice Minimal token balance surface used by fork-read helpers.
interface IERC20BalanceReaderLike {
    function balanceOf(address account) external view returns (uint256);
}

/// @title ForkUtils
/// @author Phylax Systems
/// @notice Shared fork-aware read and ERC20-delta helpers for assertions and protection suites.
abstract contract ForkUtils is Credible {
    /// @notice Gas forwarded to snapshot-time protocol view calls made through `ph.staticcallAt`.
    uint64 internal constant FORK_VIEW_GAS = 500_000;

    /// @notice Revert string used when a fork-time static call fails.
    /// @dev Override this when a more specific failure message is useful for a derived contract.
    function _viewFailureMessage() internal pure virtual returns (string memory) {
        return "staticcallAt failed";
    }

    /// @notice Executes a static call against `target` at a specific snapshot fork.
    /// @param target The protocol contract to query.
    /// @param data ABI-encoded calldata for the target view.
    /// @param fork The snapshot fork the read should execute against.
    /// @return resultData Raw return bytes from the static call.
    function _viewAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bytes memory resultData)
    {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(target, data, FORK_VIEW_GAS, fork);
        require(result.ok, _viewFailureMessage());
        return result.data;
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint256`.
    function _readUintAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        return abi.decode(_viewAt(target, data, fork), (uint256));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint8`.
    function _readUint8At(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint8 value)
    {
        return abi.decode(_viewAt(target, data, fork), (uint8));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `address`.
    function _readAddressAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (address value)
    {
        return abi.decode(_viewAt(target, data, fork), (address));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `bool`.
    function _readBoolAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool value)
    {
        return abi.decode(_viewAt(target, data, fork), (bool));
    }

    /// @notice Convenience wrapper that reads an ERC20-style `balanceOf(account)` at a snapshot fork.
    function _readBalanceAt(address token, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        return _readUintAt(token, abi.encodeCall(IERC20BalanceReaderLike.balanceOf, (account)), fork);
    }

    /// @notice Returns reduced ERC20 transfer deltas for a token within the selected fork scope.
    function _reducedErc20BalanceDeltasAt(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (PhEvm.Erc20TransferData[] memory deltas)
    {
        return ph.reduceErc20BalanceDeltas(token, fork);
    }

    /// @notice Returns the total amount of `token` transferred from `from` to `to` in the fork scope.
    function _transferredValueAt(address token, address from, address to, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        PhEvm.Erc20TransferData[] memory deltas = _reducedErc20BalanceDeltasAt(token, fork);

        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == from && deltas[i].to == to) {
                value += deltas[i].value;
            }
        }
    }

    /// @notice Computes the non-negative decrease between two snapshot values.
    function _consumedBetween(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256 consumed) {
        return beforeValue > afterValue ? beforeValue - afterValue : 0;
    }
}
