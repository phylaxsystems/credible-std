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

    // Call inputs for the getCallInputs precompile
    struct CallInputs {
        // The call data of the call.
        bytes input;
        /// The gas limit of the call.
        uint64 gas_limit;
        // The account address of bytecode that is going to be executed.
        //
        // Previously `context.code_address`.
        address bytecode_address;
        // Target address, this account storage is going to be modified.
        //
        // Previously `context.address`.
        address target_address;
        // This caller is invoking the call.
        //
        // Previously `context.caller`.
        address caller;
        // Call value.
        //
        // NOTE: This value may not necessarily be transferred from caller to callee, see [`CallValue`].
        //
        // Previously `transfer.value` or `context.apparent_value`.
        uint256 value;
    }

    //Forks to the state prior to the assertion triggering transaction.
    function forkPreState() external;

    // Forks to the state after the assertion triggering transaction.
    function forkPostState() external;

    // Loads a storage slot from an address
    function load(address target, bytes32 slot) external view returns (bytes32 data);

    // Get the logs from the assertion triggering transaction.
    function getLogs() external returns (Log[] memory logs);

    // Get the call inputs for a given target and selector
    function getCallInputs(address target, bytes4 selector) external view returns (CallInputs[] memory calls);

    // Get state changes for a given slot
    function getStateChanges(bytes32 slot) external returns (bytes32[] memory);
}
