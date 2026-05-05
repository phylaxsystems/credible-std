// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../PhEvm.sol";

/// @title LogUtils
/// @author Phylax Systems
/// @notice Pure utility library for matching, filtering, and decoding EVM logs returned by
///         `getLogs()` or `getLogsQuery()`. All functions operate on in-memory `PhEvm.Log`
///         structs and do not call any precompiles.
/// @dev Implemented with `internal` functions so they inline at the call site and avoid
///      external call overhead.
library LogUtils {
    // ---- Event Matching ----

    /// @notice Returns topic[0] of the log, or bytes32(0) if no topics.
    function sig(PhEvm.Log memory log) internal pure returns (bytes32) {
        if (log.topics.length == 0) return bytes32(0);
        return log.topics[0];
    }

    /// @notice True if log.topics[0] == eventSig.
    function isSig(PhEvm.Log memory log, bytes32 eventSig) internal pure returns (bool) {
        return sig(log) == eventSig;
    }

    /// @notice True if log.emitter == emitter.
    function isFrom(PhEvm.Log memory log, address emitter) internal pure returns (bool) {
        return log.emitter == emitter;
    }

    /// @notice True if log matches both emitter and eventSig.
    function isEvent(PhEvm.Log memory log, address emitter, bytes32 eventSig) internal pure returns (bool) {
        return isFrom(log, emitter) && isSig(log, eventSig);
    }

    // ---- Indexed Topic Access ----

    /// @notice Returns topics[indexedIdx + 1] as raw bytes32. Reverts if out of bounds.
    /// @dev The `+1` skips topic[0] (the event signature).
    function indexedTopic(PhEvm.Log memory log, uint256 indexedIdx) internal pure returns (bytes32) {
        return log.topics[indexedIdx + 1];
    }

    /// @notice Decodes indexed param as address.
    function indexedAddress(PhEvm.Log memory log, uint256 indexedIdx) internal pure returns (address) {
        return address(uint160(uint256(indexedTopic(log, indexedIdx))));
    }

    /// @notice Decodes indexed param as uint256.
    function indexedUint(PhEvm.Log memory log, uint256 indexedIdx) internal pure returns (uint256) {
        return uint256(indexedTopic(log, indexedIdx));
    }

    /// @notice Decodes indexed param as bool.
    function indexedBool(PhEvm.Log memory log, uint256 indexedIdx) internal pure returns (bool) {
        return uint256(indexedTopic(log, indexedIdx)) != 0;
    }

    // ---- Topic Encoding ----

    /// @notice Encodes address as topic-compatible bytes32 (left-pads 20 bytes to 32).
    function topic(address value) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(value)));
    }

    /// @notice Encodes uint256 as topic-compatible bytes32.
    function topic(uint256 value) internal pure returns (bytes32) {
        return bytes32(value);
    }

    // ---- Array Helpers ----

    /// @notice Returns the first log matching (emitter, eventSig).
    /// @return found True if a matching log was found.
    /// @return log The first matching log, or an empty log if none found.
    function first(PhEvm.Log[] memory logs, address emitter, bytes32 eventSig)
        internal
        pure
        returns (bool found, PhEvm.Log memory log)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (isEvent(logs[i], emitter, eventSig)) {
                return (true, logs[i]);
            }
        }
    }

    /// @notice Counts logs matching (emitter, eventSig).
    function count(PhEvm.Log[] memory logs, address emitter, bytes32 eventSig) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (isEvent(logs[i], emitter, eventSig)) n++;
        }
    }
}
