// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../src/Assertion.sol";
import {MockPhEvm} from "./MockPhEvm.sol";
import {PhEvm} from "../../src/PhEvm.sol";
import {Vm} from "forge-std/Vm.sol";

contract MockAssertion is Assertion {
    constructor() {
        address mockPhEvm = address(new MockPhEvm());
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        bytes memory runtimeCode;
        assembly {
            let size := extcodesize(mockPhEvm)
            runtimeCode := mload(0x40)
            mstore(0x40, add(runtimeCode, add(size, 0x20)))
            mstore(runtimeCode, size)
            extcodecopy(mockPhEvm, add(runtimeCode, 0x20), 0, size)
        }
        vm.etch(address(ph), runtimeCode);
        MockPhEvm(address(ph)).initialize();
    }

    function triggers() external view override {
        registerCallTrigger(this.assertionTrue.selector);
    }

    function assertionTrue() public pure returns (bool) {
        return true;
    }
}
