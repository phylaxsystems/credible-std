// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";

/**
 * @title StateChanges
 * @notice Helper contract for converting state changes from bytes32 arrays to typed arrays
 * @dev Inherits from Credible to access the PhEvm interface
 */
contract StateChanges is Credible {
    /**
     * @notice Converts state changes for a slot to uint256 array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as uint256 values
     */
    function getStateChangesUint(address contractAddress, bytes32 slot) internal view returns (uint256[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        // Explicit cast to uint256[]
        uint256[] memory uintChanges;
        assembly {
            uintChanges := stateChanges
        }

        return uintChanges;
    }

    /**
     * @notice Converts state changes for a slot to address array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as address values
     */
    function getStateChangesAddress(address contractAddress, bytes32 slot) internal view returns (address[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        assembly {
            // Zero out the upper 96 bits for each element to ensure clean address casting
            for { let i := 0 } lt(i, mload(stateChanges)) { i := add(i, 1) } {
                let addr :=
                    and(
                        mload(add(add(stateChanges, 0x20), mul(i, 0x20))),
                        0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff
                    )
                mstore(add(add(stateChanges, 0x20), mul(i, 0x20)), addr)
            }
        }

        // Explicit cast to address[]
        address[] memory addressChanges;
        assembly {
            addressChanges := stateChanges
        }

        return addressChanges;
    }

    /**
     * @notice Converts state changes for a slot to boolean array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as boolean values
     */
    function getStateChangesBool(address contractAddress, bytes32 slot) internal view returns (bool[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        assembly {
            // Convert each bytes32 to bool
            for { let i := 0 } lt(i, mload(stateChanges)) { i := add(i, 1) } {
                // Any non-zero value is true, zero is false
                let boolValue := iszero(iszero(mload(add(add(stateChanges, 0x20), mul(i, 0x20)))))
                mstore(add(add(stateChanges, 0x20), mul(i, 0x20)), boolValue)
            }
        }

        // Explicit cast to bool[]
        bool[] memory boolChanges;
        assembly {
            boolChanges := stateChanges
        }

        return boolChanges;
    }

    /**
     * @notice Gets raw state changes as bytes32 array
     * @param contractAddress The address of the contract to get state changes from
     * @param slot The storage slot to get state changes for
     * @return Array of state changes as bytes32 values
     */
    function getStateChangesBytes32(address contractAddress, bytes32 slot) internal view returns (bytes32[] memory) {
        return ph.getStateChanges(contractAddress, slot);
    }

    /**
     * @notice Calculates the storage slot for a mapping with a given key and offset
     * @param slot The base storage slot of the mapping
     * @param key The key in the mapping
     * @param offset Additional offset to add to the calculated slot
     * @return The storage slot for the mapping entry
     */
    function getSlotMapping(bytes32 slot, uint256 key, uint256 offset) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(key, slot))) + offset);
    }

    // Helper functions for mapping access with keys

    /**
     * @notice Gets uint256 state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as uint256 values
     */
    function getStateChangesUint(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (uint256[] memory)
    {
        return getStateChangesUint(contractAddress, slot, key, 0);
    }

    /**
     * @notice Gets address state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as address values
     */
    function getStateChangesAddress(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (address[] memory)
    {
        return getStateChangesAddress(contractAddress, slot, key, 0);
    }

    /**
     * @notice Gets boolean state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as boolean values
     */
    function getStateChangesBool(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (bool[] memory)
    {
        return getStateChangesBool(contractAddress, slot, key, 0);
    }

    /**
     * @notice Gets bytes32 state changes for a mapping entry
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @return Array of state changes as bytes32 values
     */
    function getStateChangesBytes32(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(contractAddress, slot, key, 0);
    }

    // Helper functions for mapping access with keys and offsets

    /**
     * @notice Gets uint256 state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as uint256 values
     */
    function getStateChangesUint(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (uint256[] memory)
    {
        return getStateChangesUint(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    /**
     * @notice Gets address state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as address values
     */
    function getStateChangesAddress(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (address[] memory)
    {
        return getStateChangesAddress(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    /**
     * @notice Gets boolean state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as boolean values
     */
    function getStateChangesBool(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (bool[] memory)
    {
        return getStateChangesBool(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    /**
     * @notice Gets bytes32 state changes for a mapping entry with offset
     * @param contractAddress The contract address
     * @param slot The mapping's slot
     * @param key The mapping key
     * @param slotOffset Additional offset to add to the slot
     * @return Array of state changes as bytes32 values
     */
    function getStateChangesBytes32(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(contractAddress, getSlotMapping(slot, key, slotOffset));
    }
}
