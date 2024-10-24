// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Credible} from "../src/Credible.sol";

contract PhEvmTest is Credible, Test {
    function testAddress() public view {
        assertEq(address(ph), address(0x15FDfe40Eee261663f48262DA81bf13232C63741));
    }
}
