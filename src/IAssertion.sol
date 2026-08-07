// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IAssertion
/// @notice Runtime entrypoint the assertion extractor invokes after deployment.
interface IAssertion {
    /// @notice Registers the assertion's triggers with the trigger recorder.
    function triggers() external view;
}
