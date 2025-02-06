// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Vm} from "../lib/forge-std/src/Vm.sol";

interface VmEx is Vm {
    function assertionEx(bytes calldata tx, address assertionAdopter, bytes calldata assertions, string calldata label)
        external;
}

contract CLTestEnv {
    struct AssertionTransaction {
        address from;
        address to;
        uint256 value;
        bytes data;
    }

    VmEx public immutable vmEx;
    mapping(string => bytes) public labelToAssertions;
    mapping(string => address[]) public assertionLabelToAdopters;

    constructor(address vm_address) {
        vmEx = VmEx(vm_address);
    }

    function addAssertion(
        string memory label,
        address assertionAdopter,
        bytes memory assertionCode,
        bytes memory constructorArgs
    ) external {
        bytes memory assertion = abi.encodePacked(assertionCode, constructorArgs);
        assertionLabelToAdopters[label].push(assertionAdopter);
        labelToAssertions[label] = assertion;
    }

    function validate(string memory label, address to, uint256 value, bytes calldata data) external {
        for (uint256 i = 0; i < assertionLabelToAdopters[label].length; i++) {
            address assertionAdopter = assertionLabelToAdopters[label][i];
            vmEx.assertionEx(
                abi.encode(AssertionTransaction({from: msg.sender, to: to, value: value, data: data})),
                assertionAdopter,
                labelToAssertions[label],
                label
            );
        }
    }
}
