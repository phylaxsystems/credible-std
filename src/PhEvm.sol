// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface PhEvm {
    // An Ethereum log
    struct Log {
        // The topics of the log, including the signature, if any.
        bytes32[] topics;
        // The raw data of the log.
        bytes data;
        // The address of the log's emitter.
        address emitter;
    }

    //Forks to the state prior to the assertion triggering transaction.
    function forkPreState() external;

    //Forks to the state after the assertion triggering transaction.
    function forkPostState() external;

    // Get the logs from the assertion triggering transaction.
    function getLogs() external returns (Log[] memory logs);
}
