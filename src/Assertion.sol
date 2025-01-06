// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Credible} from "./Credible.sol";

/// @notice Assertion interface for the PhEvm precompile
abstract contract Assertion is Credible {
    /// @notice Returns all the fn selectors for the assertion contract
    /// @return An array of bytes4 selectors
    function fnSelectors() external pure virtual returns (bytes4[] memory);
}
