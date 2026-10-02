// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from "../lib/forge-std/src/Vm.sol";

/// @title VmEx
/// @notice Extended Vm interface with assertion testing capabilities
/// @dev Extends the standard Forge Vm interface with Credible Layer specific cheatcodes
interface VmEx is Vm {
    /// @notice Register an assertion for testing
    /// @param adopter The address of the contract that adopts the assertion
    /// @param createData The creation bytecode of the assertion contract
    /// @param fnSelector The function selector of the assertion function to test
    function assertion(address adopter, bytes calldata createData, bytes4 fnSelector) external;

    /// @notice Stage the anomaly verdict returned for `target` on the next `assertion` call
    /// @dev A `watchAnomaly` trigger registered at level `L` fires iff `firesAt != 0 && L >= firesAt`.
    ///      Targets that are not staged are not scored, so their anomaly triggers never fire.
    ///      Call once per target to stage several before `assertion`.
    /// @param target The contract the verdict is for (the `watchAnomaly` target)
    /// @param firesAt The strictest sensitivity level (1..=10) the score clears; 0 clears none
    function setAnomalyLevel(address target, uint8 firesAt) external;
}

/// @title CredibleTest
/// @author Phylax Systems
/// @notice Base contract for testing Credible Layer assertions with Forge
/// @dev Inherit from this contract (or CredibleTestWithBacktesting) to test assertions locally
contract CredibleTest {
    /// @notice The extended Vm cheatcode interface for assertion testing
    /// @dev Provides access to assertion-specific cheatcodes
    VmEx public constant cl = VmEx(address(uint160(uint256(keccak256("hevm cheat code")))));
}
