// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Credible} from "../../Credible.sol";
import {PhEvm} from "../../PhEvm.sol";
import {PerpetualProtectionSuiteAdapter} from "./PerpetualProtectionSuiteAdapter.sol";

/// @notice Minimal token balance surface used by perpetual protection helpers.
interface IERC20PerpetualBalanceReaderLike {
    function balanceOf(address account) external view returns (uint256);
}

/// @title PerpetualProtectionSuiteBase
/// @author Phylax Systems
/// @notice Shared snapshot-read helpers for perpetual protection suites.
abstract contract PerpetualProtectionSuiteBase is Credible, PerpetualProtectionSuiteAdapter {
    /// @notice Gas forwarded to snapshot-time protocol view calls made through `ph.staticcallAt`.
    uint64 internal constant SUITE_VIEW_GAS = 500_000;

    /// @notice Executes a static call against `target` at a specific snapshot fork.
    function _suiteViewAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bytes memory resultData)
    {
        PhEvm.StaticCallResult memory result = ph.staticcallAt(target, data, SUITE_VIEW_GAS, fork);
        require(result.ok, "perpetual suite staticcall failed");
        return result.data;
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint256`.
    function _suiteReadUintAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (uint256));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `int256`.
    function _suiteReadIntAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (int256 value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (int256));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `uint8`.
    function _suiteReadUint8At(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint8 value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (uint8));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `address`.
    function _suiteReadAddressAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (address value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (address));
    }

    /// @notice Convenience wrapper that decodes a snapshot-time static call as `bool`.
    function _suiteReadBoolAt(address target, bytes memory data, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool value)
    {
        return abi.decode(_suiteViewAt(target, data, fork), (bool));
    }

    /// @notice Convenience wrapper that reads an ERC20-style `balanceOf(account)` at a snapshot fork.
    function _suiteReadBalanceAt(address token, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        return _suiteReadUintAt(token, abi.encodeCall(IERC20PerpetualBalanceReaderLike.balanceOf, (account)), fork);
    }

    /// @notice Returns the raw return bytes for a traced call.
    function _suiteCallOutputAt(uint256 callId) internal view returns (bytes memory output) {
        return ph.callOutputAt(callId);
    }

    /// @notice Decodes the raw output for a traced call as a single `uint256`.
    function _suiteReadUint256OutputAt(uint256 callId) internal view returns (uint256 value) {
        return abi.decode(_suiteCallOutputAt(callId), (uint256));
    }

    /// @notice Decodes the raw output for a traced call as a single `int256`.
    function _suiteReadInt256OutputAt(uint256 callId) internal view returns (int256 value) {
        return abi.decode(_suiteCallOutputAt(callId), (int256));
    }

    /// @notice Returns reduced ERC20 transfer deltas for a token within the selected fork scope.
    function _suiteReducedErc20BalanceDeltasAt(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (PhEvm.Erc20TransferData[] memory deltas)
    {
        return ph.reduceErc20BalanceDeltas(token, fork);
    }

    /// @notice Returns the total amount of `token` transferred from `from` to `to` in the fork scope.
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
    function _consumedBetween(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256 consumed) {
        return beforeValue > afterValue ? beforeValue - afterValue : 0;
    }
}
