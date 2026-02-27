// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice The assertion spec defines what subset of precompiles are available.
/// All new specs derive and expose all precompiles from the old definitions,
/// unless specified otherwise.
enum AssertionSpec {
    /// @notice Standard set of PhEvm precompiles available at launch.
    Legacy,
    /// @notice Contains tx object precompiles.
    Reshiram,
    /// @notice Unrestricted access to all available precompiles. May be untested and dangerous.
    Experimental
}

/// @title SpecRecorder
/// @author Phylax Systems
/// @notice Precompile interface for registering the desired assertion spec
/// @dev Used within the constructor of assertion contracts to specify which
/// subset of PhEvm precompiles should be available during assertion execution.
/// You can only call registerAssertionSpec once per assertion.
interface SpecRecorder {
    /// @notice Called within the constructor to set the desired assertion spec.
    /// The assertion spec defines what subset of precompiles are available.
    /// You can only call this function once. For an assertion to be valid,
    /// it needs to have a defined spec.
    /// @param spec The desired AssertionSpec.
    function registerAssertionSpec(AssertionSpec spec) external view;
}
