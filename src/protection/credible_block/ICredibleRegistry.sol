// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title ICredibleRegistry
/// @author Phylax Systems
/// @notice Read interface for the on-chain Credible Registry that tracks which blocks were
///         marked credible by authorized credible block builders.
/// @dev Mirrors the read surface of `phylaxsystems/credible-registry` so consumers such as
///      {CredibleBlockGuard} are drop-in compatible with the deployed registry. The registry
///      records block credibility by block number; it does not expose timestamps.
interface ICredibleRegistry {
    /// @notice Returns whether the current nonzero block is credible.
    /// @dev Also returns true for zero-gas-price simulations. Use lastCredibleBlock() to
    ///      distinguish a stored marker from the simulation bypass.
    /// @return True if the current block is marked credible or the simulation bypass applies.
    function isCredibleBlock() external view returns (bool);

    /// @notice Returns the most recent block number that was marked credible.
    /// @dev Returns 0 if no block has ever been marked credible.
    /// @return The highest block number marked credible so far.
    function lastCredibleBlock() external view returns (uint256);
}
