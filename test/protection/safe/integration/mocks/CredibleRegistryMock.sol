// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICredibleRegistry} from "credible-std/protection/safe/ICredibleRegistry.sol";

/// @notice Test double for the Credible Registry. Exposes fine-grained setters plus a faithful
///         `markCurrentBlockCredible()` replicating `phylaxsystems/credible-registry` semantics.
contract CredibleRegistryMock is ICredibleRegistry {
    mapping(uint256 blockNumber => bool credible) internal _credible;
    uint256 internal _lastCredibleBlock;

    function setCredibleBlock(uint256 blockNumber, bool credible) external {
        _credible[blockNumber] = credible;
    }

    function setLastCredibleBlock(uint256 blockNumber) external {
        _lastCredibleBlock = blockNumber;
    }

    /// @dev Mirrors the real registry: marks `block.number` credible and advances the pointer.
    function markCurrentBlockCredible() external {
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
