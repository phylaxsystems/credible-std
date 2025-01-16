// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {Assertion} from "./Assertion.sol";
import {CLTestEnv, VmEx} from "./CLTestEnv.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";

contract CredibleTest is Test {
    CLTestEnv cl = new CLTestEnv(VM_ADDRESS);
    VmEx clVm = cl.vmEx();
}
