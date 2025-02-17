// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";
import {TriggerRecorder} from "./TriggerRecorder.sol";

/// @notice Assertion interface for the PhEvm precompile
abstract contract Assertion is Credible {
    //Trigger recorder address
    TriggerRecorder constant triggerRecorder = TriggerRecorder(address(uint160(uint256(keccak256("TriggerRecorder")))));

    /// @notice Used to record fn selectors and their triggers.
    function triggers() external view virtual;

    /// @notice Registers a call trigger for the specified assertion function.
    function registerCallTrigger(bytes4 fnSelector) internal view {
        triggerRecorder.registerCallTrigger(fnSelector);
    }

    function getStateChangesUint(bytes32 slot) internal view returns (uint256[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(slot);

        // Explicit cast to uint256[]
        uint256[] memory uintChanges;
        assembly {
            uintChanges := stateChanges
        }

        return uintChanges;
    }

    function getStateChangesAddress(bytes32 slot) internal view returns (address[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(slot);

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

    function getStateChangesBool(bytes32 slot) internal view returns (bool[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(slot);

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

    function getStateChangesBytes32(bytes32 slot) internal view virtual returns (bytes32[] memory) {
        return ph.getStateChanges(slot);
    }

    function getSlotMapping(bytes32 slot, uint256 key, uint256 offset) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked(key, slot))) + offset);
    }

    function getStateChangesUint(bytes32 slot, uint256 key) internal view virtual returns (uint256[] memory) {
        return getStateChangesUint(slot, key, 0);
    }

    function getStateChangesAddress(bytes32 slot, uint256 key) internal view virtual returns (address[] memory) {
        return getStateChangesAddress(slot, key, 0);
    }

    function getStateChangesBool(bytes32 slot, uint256 key) internal view virtual returns (bool[] memory) {
        return getStateChangesBool(slot, key, 0);
    }

    function getStateChangesBytes32(bytes32 slot, uint256 key) internal view virtual returns (bytes32[] memory) {
        return getStateChangesBytes32(slot, key, 0);
    }

    function getStateChangesUint(bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        virtual
        returns (uint256[] memory)
    {
        return getStateChangesUint(getSlotMapping(slot, key, slotOffset));
    }

    function getStateChangesAddress(bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        virtual
        returns (address[] memory)
    {
        return getStateChangesAddress(getSlotMapping(slot, key, slotOffset));
    }

    function getStateChangesBool(bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        virtual
        returns (bool[] memory)
    {
        return getStateChangesBool(getSlotMapping(slot, key, slotOffset));
    }

    function getStateChangesBytes32(bytes32 slot, uint256 key, uint256 slotOffset)
        internal
        view
        virtual
        returns (bytes32[] memory)
    {
        return getStateChangesBytes32(getSlotMapping(slot, key, slotOffset));
    }
}
