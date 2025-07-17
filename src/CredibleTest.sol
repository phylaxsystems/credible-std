// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from "../lib/forge-std/src/Vm.sol";

interface VmEx is Vm {
    function assertion(string calldata label, address adopter, bytes calldata createData, bytes4 fnSelector) external;
}

contract CredibleTest {
    VmEx public constant ph = VmEx(address(uint160(uint256(keccak256("hevm cheat code")))));
}
