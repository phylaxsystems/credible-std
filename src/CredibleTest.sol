// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {Assertion} from "./Assertion.sol";
import {CLTestEnv, VmEx} from "./CLTestEnv.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";

contract CredibleTest {
    CLTestEnv cl = new CLTestEnv();
    VmEx clVm = cl.vmEx();
}
