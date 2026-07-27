// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IInitialProtocolManager
/// @author Phylax Systems
/// @notice Interface a protected contract exposes to declare the address allowed to manage its
///         assertions in the Credible Layer. Every protected contract needs a protocol manager;
///         exposing the intended manager on the contract itself lets the state oracle set it
///         without a manual review round.
/// @dev The state oracle calls {initialProtocolManager} on the contract when the protocol is
///      initialized in the Credible Layer and registers the returned address as the manager.
///      Because the value is defined by the contract's own code, deploying the contract is the
///      ownership proof: whoever controlled the deployment chose the manager. This is what makes
///      updated or redeployed contracts self-verifying, with no separate claim step.
///
///      Implementing this interface is optional. Contracts that do not expose it (for example,
///      already-deployed contracts that cannot be changed) go through manual verification, where
///      Phylax confirms ownership directly and sets the manager.
interface IInitialProtocolManager {
    /// @notice The address to set as this contract's protocol manager when the protocol is
    ///         initialized in the Credible Layer.
    /// @return The intended initial protocol manager address.
    function initialProtocolManager() external view returns (address);
}
