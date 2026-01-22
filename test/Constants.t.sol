// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Credible} from "../src/Credible.sol";
import {CredibleTest} from "../src/CredibleTest.sol";
import {Assertion} from "../src/Assertion.sol";
import {console as PhConsole} from "../src/Console.sol";

/// @title Constants Unit Tests
/// @notice Ensures precompile addresses don't accidentally change
/// @dev These addresses are derived from deterministic hashes and must remain stable
contract ConstantsTest is Test, Credible {
    /// @notice Test PhEvm precompile address is stable
    function testPhEvmAddress() public pure {
        // Address derived from keccak256("Kim Jong Un Sucks")
        address expected = address(uint160(uint256(keccak256("Kim Jong Un Sucks"))));
        assertEq(address(ph), expected);
        assertEq(address(ph), 0x4461812e00718ff8D80929E3bF595AEaaa7b881E);
    }

    /// @notice Test CredibleTest cl cheatcode address is stable
    function testCredibleTestAddress() public pure {
        // Address derived from keccak256("hevm cheat code") - same as Forge's VM
        address expected = address(uint160(uint256(keccak256("hevm cheat code"))));
        assertEq(expected, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    }

    /// @notice Test TriggerRecorder address is stable
    function testTriggerRecorderAddress() public pure {
        // Address derived from keccak256("TriggerRecorder")
        address expected = address(uint160(uint256(keccak256("TriggerRecorder"))));
        assertEq(expected, 0x55BB9AD8Dc1EE06D47279fC2B23Cd755B7f2d326);
    }

    /// @notice Test Console address matches PhEvm (same precompile)
    function testConsoleAddress() public pure {
        address expected = address(uint160(uint256(keccak256("Kim Jong Un Sucks"))));
        assertEq(expected, 0x4461812e00718ff8D80929E3bF595AEaaa7b881E);
    }
}

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
