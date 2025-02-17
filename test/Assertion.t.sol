// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MockAssertion} from "./mocks/MockAssertion.sol";

contract AssertionTest is Test, MockAssertion {
    function testStateChanges() public view {
        bytes32[] memory stateChanges = ph.getStateChanges(0x0);
        assertEq(stateChanges.length, 3);
        assertEq(stateChanges[0], bytes32(uint256(0x0)));
        assertEq(stateChanges[1], bytes32(uint256(0x1)));
        assertEq(stateChanges[2], bytes32(type(uint256).max));
    }

    function testStateChangesUint() public view {
        uint256[] memory stateChanges = getStateChangesUint(0x0);
        assertEq(stateChanges.length, 3);
        assertEq(stateChanges[0], 0x0);
        assertEq(stateChanges[1], 0x1);
        assertEq(stateChanges[2], type(uint256).max);
    }

    function testStateChangesAddress() public view {
        address[] memory stateChanges = getStateChangesAddress(0x0);
        assertEq(stateChanges.length, 3);
        assertEq(stateChanges[0], address(0x0));
        assertEq(stateChanges[1], address(0x1));
        assertEq(stateChanges[2], address(type(uint160).max));
        assertEq(uint256(uint160(stateChanges[2])), uint256(type(uint160).max));
    }

    function testStateChangesBool() public view {
        bool[] memory stateChanges = getStateChangesBool(0x0);
        assertEq(stateChanges.length, 3);
        assertEq(stateChanges[0], false);
        assertEq(stateChanges[1], true);
        assertEq(stateChanges[2], true);

        // Precise bit check in assembly
        bool maxValue = stateChanges[2];
        uint256 isExactlyOne;
        assembly {
            isExactlyOne := eq(maxValue, 1)
        }

        assertEq(isExactlyOne, 1);
    }
}
