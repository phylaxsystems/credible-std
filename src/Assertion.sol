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

    function getStateChangesUint(bytes32 slot) internal returns (uint256[] memory) {
        bytes32[] memory stateChanges = ph.getStateChanges(slot);

        assembly {
            // Return the same memory location, but interpreted as uint256[]
            return(add(stateChanges, 0), mload(stateChanges))
        }
    }

    function getStateChangesAddress(bytes32 slot) internal returns (address[] calldata) {
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

            // Return the modified memory as address[]
            return(add(stateChanges, 0), mload(stateChanges))
        }
    }

    function getStateChangesBool(bytes32 slot) internal returns (bool[] calldata) {
        bytes32[] memory stateChanges = ph.getStateChanges(slot);

        assembly {
            // Convert each bytes32 to bool
            for { let i := 0 } lt(i, mload(stateChanges)) { i := add(i, 1) } {
                // Any non-zero value is true, zero is false
                let boolValue := iszero(iszero(mload(add(add(stateChanges, 0x20), mul(i, 0x20)))))
                mstore(add(add(stateChanges, 0x20), mul(i, 0x20)), boolValue)
            }

            // Return the modified memory as bool[]
            return(add(stateChanges, 0), mload(stateChanges))
        }
    }
}
