// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Credible} from "../src/Credible.sol";

contract PhEvmTest is Test, Credible {
    function testAddress() public view {
        assertEq(address(ph), address(0x4461812e00718ff8D80929E3bF595AEaaa7b881E));
    }
}
