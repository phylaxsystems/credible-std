// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {IInitialProtocolManager} from "../../../src/protection/initial_protocol_manager/IInitialProtocolManager.sol";
import {InitialProtocolManager} from "../../../src/protection/initial_protocol_manager/InitialProtocolManager.sol";

/// @notice Minimal concrete contract that inherits the abstract base by forwarding the manager
///         address to its constructor, mirroring the intended inherit-and-forward usage.
contract ProtectedContract is InitialProtocolManager {
    constructor(address manager) InitialProtocolManager(manager) {}
}

contract InitialProtocolManagerTest is Test {
    address internal constant MANAGER = address(0xA11CE);

    ProtectedContract internal protectedContract;

    function setUp() public {
        protectedContract = new ProtectedContract(MANAGER);
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    function test_constructor_storesManager() public view {
        assertEq(protectedContract.initialProtocolManager(), MANAGER);
    }

    function test_constructor_revertsOnZeroManager() public {
        vm.expectRevert(InitialProtocolManager.ZeroInitialProtocolManager.selector);
        new ProtectedContract(address(0));
    }

    function testFuzz_constructor_storesAnyNonZeroManager(address manager) public {
        vm.assume(manager != address(0));
        ProtectedContract instance = new ProtectedContract(manager);
        assertEq(instance.initialProtocolManager(), manager);
    }

    // ---------------------------------------------------------------------
    // Interface conformance
    // ---------------------------------------------------------------------

    /// @dev The state oracle reads the manager through {IInitialProtocolManager}, so the public
    ///      immutable must satisfy that interface's getter when called through the interface type.
    function test_conformsToInterface() public view {
        IInitialProtocolManager asInterface = IInitialProtocolManager(address(protectedContract));
        assertEq(asInterface.initialProtocolManager(), MANAGER);
    }
}
