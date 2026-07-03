// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICredibleRegistry} from "./ICredibleRegistry.sol";

/// @title CredibleBlockGuard
/// @author Phylax Systems
/// @notice Reusable mixin that gates functions on block credibility. Inherit it and apply the
///         {onlyCredibleBlock} modifier to any function that should only execute while the
///         current block is credible, i.e. built by a Credible Layer builder that enforces
///         assertions. When the credible builder set is offline the guard fails open so the
///         protected contract is never bricked.
/// @dev This is the general-purpose form of the credibility gate. {CredibleSafeGuard} is the
///      same decision wired into a Safe transaction guard; protocols that want to protect their
///      own functions directly should inherit this contract instead.
///
///      Decision in {_checkCredibleBlock} (run by {onlyCredibleBlock} before the function body):
///      1. If the credible builder set looks offline (the most recent credible block is more
///         than `failOpenBlockThreshold` blocks behind the current block), FAIL OPEN and allow
///         the call. This prevents a stalled builder set from permanently locking the contract.
///      2. Otherwise the builder set is live, so the current block MUST be credible; if it is
///         not, the call is blocked with {NonCredibleBlock}.
///      3. If the current block is itself credible, the call is always allowed.
///
///      Fail-open window. The product requirement is "fail open after ~15 minutes with no
///      credible blocks". The {ICredibleRegistry} records credibility by block number and does
///      not expose timestamps, so the window is expressed as a block count that the credible
///      builder set would produce in ~15 minutes on the target chain, e.g.:
///        - ~12s blocks (Ethereum mainnet): 15 min  ~= 75 blocks
///        - ~2s blocks  (typical L2):       15 min  ~= 450 blocks
///        - ~1s blocks:                     15 min  ~= 900 blocks
///      Both the registry address and the fail-open threshold are immutable; re-pointing or
///      re-tuning means redeploying the inheriting contract. (Configurable per deployment.)
abstract contract CredibleBlockGuard {
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

    /// @notice Reverts the call unless the current block is credible or the guard is failing open.
    /// @dev Apply to any function that must only run under credible-block protection.
    modifier onlyCredibleBlock() {
        _checkCredibleBlock();
        _;
    }

    /// @notice Whether a call guarded by {onlyCredibleBlock} would currently be allowed.
    /// @dev View helper mirroring {_checkCredibleBlock}'s decision for off-chain inspection.
    /// @return True if the current block is credible or the guard is failing open.
    function isCurrentBlockAllowed() public view returns (bool) {
        return _failOpenActive() || credibleRegistry.isCredibleBlock(block.number);
    }

    /// @notice Whether the guard is currently failing open because the builder set looks offline.
    /// @return True if the most recent credible block lags the current block beyond the threshold.
    function failOpenActive() public view returns (bool) {
        return _failOpenActive();
    }

    /// @dev Core gate: fail open when the builder set is offline, otherwise require credibility.
    function _checkCredibleBlock() internal view {
        if (_failOpenActive()) return;
        if (!credibleRegistry.isCredibleBlock(block.number)) revert NonCredibleBlock();
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
