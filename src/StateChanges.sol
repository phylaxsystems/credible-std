// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";

contract StateChanges is Credible {
    function getStateChangesUint(address contractAddress, bytes32 slot) internal view returns (uint256[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(contractAddress, slot);

        // Explicit cast to uint256[]
        uint256[] memory uintChanges;
        assembly {
            uintChanges := stateChanges
        }

        return uintChanges;
    }

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

    function getStateChangesBytes32(address contractAddress, bytes32 slot) internal view returns (bytes32[] memory) {
        return ph.getStateChanges(contractAddress, slot);
    }

    function getSlotMapping(bytes32 slot, uint256 key, uint256 offset) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(key, slot))) + offset);
    }

    function getStateChangesUint(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (uint256[] memory)
    {
        return getStateChangesUint(contractAddress, slot, key, 0);
    }

    function getStateChangesAddress(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (address[] memory)
    {
        return getStateChangesAddress(contractAddress, slot, key, 0);
    }

    function getStateChangesBool(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (bool[] memory)
    {
        return getStateChangesBool(contractAddress, slot, key, 0);
    }

    function getStateChangesBytes32(address contractAddress, bytes32 slot, uint256 key)
        internal
        view
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(contractAddress, slot, key, 0);
    }

    function getStateChangesUint(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (uint256[] memory)
    {
        return getStateChangesUint(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    function getStateChangesAddress(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (address[] memory)
    {
        return getStateChangesAddress(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    function getStateChangesBool(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (bool[] memory)
    {
        return getStateChangesBool(contractAddress, getSlotMapping(slot, key, slotOffset));
    }

    function getStateChangesBytes32(address contractAddress, bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(contractAddress, getSlotMapping(slot, key, slotOffset));
    }
}
