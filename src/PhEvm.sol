// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface PhEvm {
    //Forks to the state prior to the assertion triggering transaction.
    function forkPreState() external;

    //Forks to the state after the assertion triggering transaction.
    function forkPostState() external;
}
