// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtectionSuite} from "../ILendingProtectionSuite.sol";
import {LendingBaseAssertion} from "../LendingBaseAssertion.sol";

/// @title AaveV3LikeOperationSafetyAssertionBase
/// @author Phylax Systems
/// @notice Shared assertion wrapper for Aave v3-like lending suites.
/// @dev The assertion holds the suite as an immutable reference rather than inheriting its bytecode.
///      Concrete bundles construct the protocol-specific suite in their own constructor and pass it
///      in. Keeping the suite in a separate contract preserves the single-`createData` deployment UX
///      while keeping the assertion runtime well below the EIP-170 size limit enforced by CI.
abstract contract AaveV3LikeOperationSafetyAssertionBase is LendingBaseAssertion {
    /// @notice Protocol-specific suite deployed alongside the assertion bundle.
    ILendingProtectionSuite internal immutable SUITE;

    constructor(ILendingProtectionSuite suite_) {
        SUITE = suite_;
    }

    function _suite() internal view override returns (ILendingProtectionSuite) {
        return SUITE;
    }
}
