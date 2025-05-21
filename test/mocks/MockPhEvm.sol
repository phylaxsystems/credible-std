// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PhEvm} from "../../src/PhEvm.sol";

contract MockPhEvm is PhEvm {
    mapping(bytes32 slot => bytes32[] stateChanges) private slotStateChanges;

    function initialize() public {
        slotStateChanges[0x0] = new bytes32[](3);
        slotStateChanges[0x0][0] = bytes32(uint256(0x0));
        slotStateChanges[0x0][1] = bytes32(uint256(0x1));
        slotStateChanges[0x0][2] = bytes32(type(uint256).max);
    }

    // Mock state changes for testing
    function getStateChanges(address, bytes32 slot) public view returns (bytes32[] memory stateChanges) {
        stateChanges = slotStateChanges[slot];
    }

    //Forks to the state prior to the assertion triggering transaction.
    function forkPreState() external {}

    // Forks to the state after the assertion triggering transaction
    function forkPostState() public {}

    // Loads a storage slot from an address
    function load(address target, bytes32 slot) public view returns (bytes32 data) {}

    // Get the logs from the assertion triggering transaction
    function getLogs() public view returns (Log[] memory logs) {}

    // Get the call inputs for a given target and selector
    function getCallInputs(address target, bytes4 selector) public view returns (CallInputs[] memory calls) {}

    // Get assertion adopter address
    function getAssertionAdopter() public view returns (address) {}
}
