// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IInitialProtocolManager} from "./IInitialProtocolManager.sol";

/// @title InitialProtocolManager
/// @author Phylax Systems
/// @notice Reusable base that implements {IInitialProtocolManager} by fixing the intended manager
///         at deployment. Inherit it and forward the manager address to the constructor; the
///         public immutable satisfies the interface's {initialProtocolManager} getter.
/// @dev The manager is immutable, so the value the state oracle reads is exactly what the deployer
///      committed to in the deployment transaction — that is the ownership proof. Changing the
///      declared manager after deployment means redeploying the inheriting contract. Once the
///      protocol is initialized in the Credible Layer, the manager is managed there rather than
///      through this value.
///
///      Example:
///      ```solidity
///      contract MyProtectedContract is InitialProtocolManager {
///          constructor(address manager) InitialProtocolManager(manager) {}
///      }
///      ```
abstract contract InitialProtocolManager is IInitialProtocolManager {
    /// @inheritdoc IInitialProtocolManager
    address public immutable initialProtocolManager;

    /// @notice Thrown when constructed with the zero address as the initial protocol manager.
    error ZeroInitialProtocolManager();

    /// @param initialProtocolManager_ The address to declare as this contract's initial protocol
    ///        manager. Must be non-zero.
    constructor(address initialProtocolManager_) {
        if (initialProtocolManager_ == address(0)) revert ZeroInitialProtocolManager();

        initialProtocolManager = initialProtocolManager_;
    }
}
