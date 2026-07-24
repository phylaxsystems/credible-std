// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICredibleRegistry} from "credible-std/protection/credible_block/ICredibleRegistry.sol";

/// @notice Minimal deployable Credible Registry for the upgrade-test scripts: just enough to seed a
///         live anvil node with "a builder we control" and let the {CredibleBlockGuard} read block
///         credibility through {ICredibleRegistry}.
/// @dev Trimmed to the essentials — a single immutable builder set at construction, one marker
///      entrypoint, and the two interface reads. The production registry
///      (`phylaxsystems/credible-registry`) adds a timelocked admin, a whitelist of builders, and
///      slot-binding by timestamp; none of that is needed to exercise the guard.
contract CredibleRegistry is ICredibleRegistry {
    /// @notice The only account allowed to mark blocks credible.
    address public immutable builder;

    mapping(uint256 blockNumber => bool credible) internal _credible;
    uint256 internal _lastCredibleBlock;

    error NotBuilder();

    constructor(address builder_) {
        builder = builder_;
    }

    /// @notice Marks the current block credible. Callable only by the builder.
    function markCurrentBlockCredible() external {
        if (msg.sender != builder) revert NotBuilder();

        _credible[block.number] = true;
        _lastCredibleBlock = block.number;
    }

    function isCredibleBlock(uint256 blockNumber) external view returns (bool) {
        return _credible[blockNumber];
    }

    function lastCredibleBlock() external view returns (uint256) {
        return _lastCredibleBlock;
    }
}
