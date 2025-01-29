// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "../lib/forge-std/src/Vm.sol";

interface VmEx is Vm {
    function assertionEx(bytes calldata tx, address assertionAdopter, bytes[] calldata assertions)
        external
        returns (bool success, uint256 gasUsed, uint256 assertionsRan);
}

contract CLTestEnv {
    struct AssertionTransaction {
        address from;
        address to;
        uint256 value;
        bytes data;
    }

    VmEx public immutable vmEx;
    mapping(address => bytes[]) public adopters;

    constructor(address vm_address) {
        vmEx = VmEx(vm_address);
    }

    function addAssertion(address assertionAdopter, bytes memory assertionCode, bytes memory constructorArgs)
        external
    {
        adopters[assertionAdopter].push(abi.encodePacked(assertionCode, constructorArgs));
    }

    function validate(address to, uint256 value, bytes calldata data) external returns (bool) {
        return vmEx.assertionEx(
            abi.encode(AssertionTransaction({from: msg.sender, to: to, value: value, data: data})), to, adopters[to]
        );
    }
}
