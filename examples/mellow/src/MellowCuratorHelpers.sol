// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

import {IMellowOracle, IMellowRiskManager} from "./MellowCuratorInterfaces.sol";

/// @title MellowCuratorHelpers
/// @author Phylax Systems
/// @notice Shared fork-aware reads, calldata decoding, and signed-integer math for the Mellow
///         curator-compromise example assertions.
/// @dev Retrieval/decoding lives here so the assertion contracts stay down to constructor,
///      `triggers()`, and the assertion functions. Everything is snapshot-scoped (PreCall/PostCall/
///      PostTx) — there is no assertion-authored persistent state.
abstract contract MellowCuratorHelpers is Assertion {
    /// @notice Reads `RiskManager.vaultState().balance` (approximate shares) at a snapshot fork.
    function _readVaultBalanceShares(address riskManager, PhEvm.ForkId memory fork)
        internal
        view
        returns (int256 balance)
    {
        (balance,) = abi.decode(
            _viewAt(riskManager, abi.encodeCall(IMellowRiskManager.vaultState, ()), fork), (int256, int256)
        );
    }

    /// @notice Reads `RiskManager.subvaultState(subvault).balance` (approximate shares) at a fork.
    function _readSubvaultBalanceShares(address riskManager, address subvault, PhEvm.ForkId memory fork)
        internal
        view
        returns (int256 balance)
    {
        (balance,) = abi.decode(
            _viewAt(riskManager, abi.encodeCall(IMellowRiskManager.subvaultState, (subvault)), fork), (int256, int256)
        );
    }

    /// @notice Best-effort read of an oracle's stored report for `asset` at a snapshot fork.
    /// @dev Uses a raw `staticcallAt` rather than `_viewAt` so a revert (asset removed during the
    ///      tx, or not yet supported) is reported as `ok == false` and skipped by the caller
    ///      instead of failing the whole assertion. Returns the 18-decimal price and the suspicious
    ///      flag; a suspicious report is recorded by the protocol but is not propagated into vault
    ///      accounting, so callers treat it as "did not reprice the vault".
    function _tryReadReportPrice(address oracle, address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool ok, uint256 priceD18, bool isSuspicious)
    {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(oracle, abi.encodeCall(IMellowOracle.getReport, (asset)), FORK_VIEW_GAS, fork);
        if (!result.ok || result.data.length < 96) {
            return (false, 0, false);
        }
        (uint224 price,, bool suspicious) = abi.decode(result.data, (uint224, uint32, bool));
        return (true, uint256(price), suspicious);
    }

    /// @notice Decodes a static (head) `address` argument from a traced call's calldata.
    /// @dev `ph.callinputAt` returns the full calldata including the 4-byte selector, so static
    ///      argument `n` lives at byte offset `4 + n*32`. Only valid for value/head types
    ///      (address, uint, bool) that occupy one word in the calldata head.
    function _callArgAddress(uint256 callId, uint256 argIndex) internal view returns (address arg) {
        bytes memory input = ph.callinputAt(callId);
        uint256 offset = 4 + argIndex * 32;
        require(input.length >= offset + 32, "Mellow: short calldata");
        bytes32 word;
        assembly {
            word := mload(add(add(input, 0x20), offset))
        }
        arg = address(uint160(uint256(word)));
    }

    /// @notice Magnitude of a signed value. Safe for realistic share balances (far from int256 min).
    function _absInt(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /// @notice Magnitude of the difference between two signed values.
    function _absDiff(int256 a, int256 b) internal pure returns (uint256) {
        return a >= b ? uint256(a - b) : uint256(b - a);
    }
}
