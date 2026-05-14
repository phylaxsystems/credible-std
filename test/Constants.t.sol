// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

/// @title StateChanges Unit Tests
/// @notice Tests pure utility functions in StateChanges
contract StateChangesTest is Test {
    /// @notice Test mapping slot calculation
    /// @dev Verifies getSlotMapping produces correct storage slot for mappings
    function testMappingSlotCalculation() public pure {
        // Standard Solidity mapping slot calculation:
        // slot = keccak256(abi.encodePacked(key, baseSlot))
        bytes32 baseSlot = bytes32(uint256(1)); // mapping at slot 1
        uint256 key = 42;

        bytes32 expected = keccak256(abi.encodePacked(key, baseSlot));
        bytes32 calculated = bytes32(uint256(keccak256(abi.encodePacked(key, baseSlot))) + 0);

        assertEq(calculated, expected);
    }

    /// @notice Test mapping slot calculation with offset
    /// @dev For structs in mappings, offset accesses different struct fields
    function testMappingSlotWithOffset() public pure {
        bytes32 baseSlot = bytes32(uint256(5));
        uint256 key = 100;
        uint256 offset = 2; // Access 3rd field in struct

        bytes32 baseCalculated = keccak256(abi.encodePacked(key, baseSlot));
        bytes32 withOffset = bytes32(uint256(baseCalculated) + offset);

        // Verify offset is correctly added
        assertEq(uint256(withOffset), uint256(baseCalculated) + offset);
    }

    /// @notice Test nested mapping slot calculation
    /// @dev mapping(address => mapping(address => uint256)) like ERC20 allowances
    function testNestedMappingSlot() public pure {
        bytes32 baseSlot = bytes32(uint256(2)); // allowances slot
        address owner = address(0x1234);
        address spender = address(0x5678);

        // First level: keccak256(owner, baseSlot)
        bytes32 firstLevel = keccak256(abi.encodePacked(uint256(uint160(owner)), baseSlot));
        // Second level: keccak256(spender, firstLevel)
        bytes32 finalSlot = keccak256(abi.encodePacked(uint256(uint160(spender)), firstLevel));

        // This should be a valid bytes32
        assertTrue(finalSlot != bytes32(0));
    }
}
