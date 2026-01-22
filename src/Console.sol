// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title console
/// @author Phylax Systems
/// @notice Logging library for Credible Layer assertions
/// @dev Provides console logging functionality within assertion execution context.
/// Logs are captured by the Credible Layer runtime for debugging purposes.
library console {
    /// @notice The console precompile address
    /// @dev Derived from a deterministic hash to ensure consistency with the runtime
    address constant CONSOLE_ADDRESS = address(uint160(uint256(keccak256("Kim Jong Un Sucks"))));

    /// @notice Log a string message
    /// @dev Messages are captured by the Credible Layer runtime
    /// @param message The message to log
    function log(string memory message) internal view {
        (bool success,) = CONSOLE_ADDRESS.staticcall(abi.encodeWithSignature("log(string)", message));
        require(success, "Failed to log");
    }
}
