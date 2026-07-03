// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICredibleRegistry} from "./ICredibleRegistry.sol";

/// @notice Minimal subset of Safe's `Enum` library, vendored so the guard does not
///         depend on the Safe contracts package.
library Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}

/// @notice ERC-165 interface (EIP-165 / OpenZeppelin `IERC165`).
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @notice Safe transaction guard interface, identical to Safe's `Guard` (v1.3.0/v1.4.1)
///         and `ITransactionGuard` (v1.5.0).
/// @dev `type(ITransactionGuard).interfaceId == 0xe6d7a83a`, the same value Safe's
///      `GuardManager.setGuard` checks via ERC-165 (error `GS300` otherwise), so a
///      {CredibleSafeGuard} can be installed on any Safe that supports transaction guards.
interface ITransactionGuard is IERC165 {
    /// @notice Called by the Safe before executing an owner-authorized transaction.
    /// @dev Reverting here blocks the Safe transaction from executing.
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external;

    /// @notice Called by the Safe after executing the transaction.
    function checkAfterExecution(bytes32 hash, bool success) external;
}

/// @title CredibleSafeGuard
/// @author Phylax Systems
/// @notice Safe transaction guard that only allows owner/multisig Safe transactions while the
///         current block is credible, i.e. built by a Credible Layer builder that enforces
///         assertions. When the credible builder set is offline the guard fails open so the Safe
///         is never bricked.
/// @dev Installed on a Safe via `setGuard(address(thisGuard))`. The Safe calls
///      {checkTransaction} before every owner-path execution; a revert blocks that execution.
///
///      Scope. This guard implements only Safe's transaction-guard interface ({ITransactionGuard}),
///      so it gates the owner/multisig `execTransaction` path only. Module executions
///      (`execTransactionFromModule`/`...ReturnData`) do not run transaction guards, so an enabled
///      module can still execute while the current block is not credible. Gating module executions
///      requires a separate Safe module guard (the v1.5.0 `checkModuleTransaction` hook) or a
///      Credible Layer assertion such as {SafeTxShapeAssertion}.
///
///      Decision in {checkTransaction}:
///      1. If the current block is credible, the transaction is always allowed.
///      2. Otherwise, if the credible builder set looks offline (the most recent credible block
///         is more than `failOpenBlockThreshold` blocks behind the current block), FAIL OPEN and
///         allow the transaction. This prevents a stalled builder set from permanently locking
///         the Safe.
///      3. Otherwise the builder set is live and the current block is not credible, so the
///         transaction is blocked with {NonCredibleBlock}.
///
///      Fail-open window. The product requirement is "fail open after ~15 minutes with no
///      credible blocks". The {ICredibleRegistry} records credibility by block number and does
///      not expose timestamps, so the window is expressed as a block count that the credible
///      builder set would produce in ~15 minutes on the target chain, e.g.:
///        - ~12s blocks (Ethereum mainnet): 15 min  ~= 75 blocks
///        - ~2s blocks  (typical L2):       15 min  ~= 450 blocks
///        - ~1s blocks:                     15 min  ~= 900 blocks
///      Both the registry address and the fail-open threshold are immutable; re-pointing or
///      re-tuning means deploying a new guard and calling `setGuard` again.
contract CredibleSafeGuard is ITransactionGuard {
    /// @notice The on-chain Credible Registry queried for block credibility.
    ICredibleRegistry public immutable credibleRegistry;

    /// @notice Number of blocks the most recent credible block may lag the current block before
    ///         the guard fails open. Should approximate the chain's 15-minute block budget.
    uint256 public immutable failOpenBlockThreshold;

    /// @notice Thrown when the current block is not credible and the builder set is live.
    error NonCredibleBlock();
    /// @notice Thrown when constructed with the zero address as the registry.
    error ZeroCredibleRegistryAddress();
    /// @notice Thrown when constructed with a zero fail-open threshold.
    error ZeroFailOpenBlockThreshold();

    /// @param credibleRegistry_ The Credible Registry address (configurable per deployment).
    /// @param failOpenBlockThreshold_ Blocks of builder silence tolerated before failing open.
    constructor(ICredibleRegistry credibleRegistry_, uint256 failOpenBlockThreshold_) {
        if (address(credibleRegistry_) == address(0)) revert ZeroCredibleRegistryAddress();
        if (failOpenBlockThreshold_ == 0) revert ZeroFailOpenBlockThreshold();

        credibleRegistry = credibleRegistry_;
        failOpenBlockThreshold = failOpenBlockThreshold_;
    }

    /// @inheritdoc ITransactionGuard
    /// @dev Reverts with {NonCredibleBlock} to block a Safe transaction. All transaction fields
    ///      are ignored: the guard only gates on whether the executing block is credible.
    function checkTransaction(
        address,
        uint256,
        bytes memory,
        Enum.Operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external view override {
        _checkCredibleBlock();
    }

    /// @inheritdoc ITransactionGuard
    /// @dev No post-execution checks are performed.
    function checkAfterExecution(bytes32, bool) external pure override {}

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ITransactionGuard).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Whether a Safe transaction would currently be allowed by this guard.
    /// @dev View helper mirroring {checkTransaction}'s decision for off-chain inspection.
    /// @return True if the current block is credible or the guard is failing open.
    function isCurrentBlockAllowed() external view returns (bool) {
        return credibleRegistry.isCredibleBlock(block.number) || _failOpenActive();
    }

    /// @notice Whether the guard is currently failing open because the builder set looks offline.
    /// @return True if the most recent credible block lags the current block beyond the threshold.
    function failOpenActive() external view returns (bool) {
        return _failOpenActive();
    }

    /// @dev Core gate: allow credible blocks, otherwise fail open only when the builder set is
    ///      offline. The credible-block check runs first so the expected hot path (credible block,
    ///      live builder set) costs a single registry call.
    function _checkCredibleBlock() internal view {
        if (credibleRegistry.isCredibleBlock(block.number)) return;
        if (!_failOpenActive()) revert NonCredibleBlock();
    }

    /// @dev Fail-open is active when the current block is strictly more than
    ///      `failOpenBlockThreshold` blocks ahead of the last credible block. The
    ///      `block.number > lastCredibleBlock_` guard avoids underflow if the registry ever
    ///      reports a last credible block at or beyond the current block.
    function _failOpenActive() internal view returns (bool) {
        uint256 lastCredibleBlock_ = credibleRegistry.lastCredibleBlock();
        return block.number > lastCredibleBlock_ && block.number - lastCredibleBlock_ > failOpenBlockThreshold;
    }
}
