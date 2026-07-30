// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {Assertion} from "../src/Assertion.sol";

contract AssertionFallbackHarness is Assertion {
    function triggers() external pure override {}

    function failingAssertion() external pure {
        revert("assertion failed");
    }
}

contract AssertionFallbackTest is Test {
    AssertionFallbackHarness internal assertion;

    function setUp() public {
        assertion = new AssertionFallbackHarness();
    }

    function testUnknownAssertionSelectorIsInert() public {
        bytes4 missingSelector = bytes4(keccak256("missingAssertion()"));

        (bool success, bytes memory returnData) = address(assertion).call(abi.encodePacked(missingSelector));

        assertTrue(success, "unknown assertion selector must not revert");
        assertEq(returnData.length, 0);
    }

    function testKnownAssertionFailureStillReverts() public {
        (bool success,) = address(assertion).call(abi.encodeCall(assertion.failingAssertion, ()));

        assertFalse(success, "real assertion failures must remain fail-closed");
    }
}
