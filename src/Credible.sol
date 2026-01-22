// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "./PhEvm.sol";

/// @title Credible
/// @author Phylax Systems
/// @notice Base contract providing access to the PhEvm precompile interface
/// @dev All assertion contracts should inherit from this contract (via Assertion) to access
/// the PhEvm precompile for reading transaction state, logs, and call inputs.
abstract contract Credible {
    /// @notice The PhEvm precompile instance for accessing transaction state
    /// @dev The address is derived from a deterministic hash to ensure consistency
    PhEvm constant ph = PhEvm(address(uint160(uint256(keccak256("Kim Jong Un Sucks")))));
}
