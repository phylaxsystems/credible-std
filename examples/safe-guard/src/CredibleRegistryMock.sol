// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICredibleRegistry} from "credible-std/protection/safe/ICredibleRegistry.sol";

/// @notice Test double for the Credible Registry. Exposes fine-grained setters plus a faithful
///         `markCurrentBlockCredible()` replicating `phylaxsystems/credible-registry` semantics.
contract CredibleRegistryMock is ICredibleRegistry {
    uint256 internal _lastCredibleBlock;

    function setLastCredibleBlock(uint256 blockNumber) external {
        _lastCredibleBlock = blockNumber;
    }

    /// @dev Mirrors the real registry: marks `block.number` credible and advances the pointer.
    function markCurrentBlockCredible() external {
        _lastCredibleBlock = block.number;
    }

    function isCredibleBlock() external view returns (bool) {
        require(msg.data.length == 4, "unexpected calldata length");
        return block.number != 0 && (block.number == _lastCredibleBlock || tx.gasprice == 0);
    }

    function lastCredibleBlock() external view returns (uint256) {
        return _lastCredibleBlock;
    }
}
