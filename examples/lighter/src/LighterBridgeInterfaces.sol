// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IZkLighterLike
/// @author Phylax Systems
/// @notice Minimal read surface of Lighter's L1 bridge / rollup contract (`ZkLighter`, the proxy at
///         `0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7` on Ethereum mainnet) needed by the example
///         assertions.
/// @dev Lighter is an app-specific ZK validity rollup; `ZkLighter` is simultaneously the funds-custody
///      bridge and the rollup state machine. The names below follow the contract's documented state
///      variables (`Storage.sol` / `ExtendableStorage.sol`).
///
///      IMPORTANT — verify before deployment: this interface assumes each value is reachable through a
///      same-named public getter. If the deployed contract keeps these as non-public variables, read
///      the corresponding storage slots with `ph.loadStateAt` instead and adjust `LighterBridgeHelpers`
///      accordingly. The `updateStateRoot` signature below is used only to derive a 4-byte selector for
///      presence detection, so only its selector — not its argument types — must match the deployment.
interface IZkLighterLike {
    /// @notice Number of batches committed (data + commitment posted) on L1.
    function committedBatchesCount() external view returns (uint256);

    /// @notice Number of committed batches whose validity proof has been verified.
    function verifiedBatchesCount() external view returns (uint256);

    /// @notice Number of verified batches whose on-chain operations (withdrawals) have executed.
    function executedBatchesCount() external view returns (uint256);

    /// @notice Number of priority requests included in committed batches.
    function committedPriorityRequestCount() external view returns (uint256);

    /// @notice Number of priority requests whose batch has been verified.
    function verifiedPriorityRequestCount() external view returns (uint256);

    /// @notice Number of priority requests whose batch has executed (or which were cancelled in
    ///         desert mode).
    function executedPriorityRequestCount() external view returns (uint256);

    /// @notice Number of priority requests queued but not yet executed.
    function openPriorityRequestCount() external view returns (uint256);

    /// @notice The current executed state root committing every L2 account balance.
    function stateRoot() external view returns (bytes32);

    /// @notice True once the escape hatch is active; irreversible.
    function desertMode() external view returns (bool);

    /// @notice Privileged one-shot, proof-gated state-root migration. Only its selector is used.
    /// @dev Verify the real signature on the deployment; only the 4-byte selector must match.
    function updateStateRoot(bytes32 oldStateRoot, bytes32 oldValidiumRoot, bytes32 newStateRoot, bytes calldata proof)
        external;
}
