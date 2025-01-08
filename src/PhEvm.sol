// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface PhEvm {
    // Forks to the state prior to the assertion triggering transaction.
    function forkPreState() external;

    // Forks to the state after the assertion triggering transaction.
    function forkPostState() external;

    // Loads a storage slot from an address
    function load(address target, bytes32 slot) external view returns (bytes32 data);

}
