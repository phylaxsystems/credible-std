// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MockAssertion} from "./mocks/MockAssertion.sol";

contract PhEvmTest is Test {
    MockAssertion mockAssertion;

    function setUp() public {
        mockAssertion = new MockAssertion();
    }

    function testAddress() public view {
        assertEq(address(mockAssertion.ph()), address(0x4461812e00718ff8D80929E3bF595AEaaa7b881E));
    }
}
