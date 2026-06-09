// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice LayerZero v2 receive entrypoint, used only for its selector.
/// @dev Cap's `OFTLockbox` is a LayerZero `OFTAdapter`. On the home chain it locks canonical
///      cUSD; remote chains mint/burn the `L2Token` representation. The adapter releases locked
///      cUSD only inside `lzReceive`, which the trusted LayerZero endpoint invokes after a remote
///      burn has been verified.
interface ILayerZeroReceiverLike {
    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable;
}
