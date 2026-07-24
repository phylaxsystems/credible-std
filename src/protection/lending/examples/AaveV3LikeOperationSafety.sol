// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtectionSuite} from "../ILendingProtectionSuite.sol";
import {LendingBaseAssertion} from "../LendingBaseAssertion.sol";

/// @title AaveV3LikeOperationSafetyAssertionBase
/// @author Phylax Systems
/// @notice Shared assertion wrapper for Aave v3-like lending suites.
/// @dev The protocol adapter lives in `AaveV3LikeHelpers.sol`. Keeping one implementation avoids
///      selector, bitmap, and call-window accounting drift between consumers.
abstract contract AaveV3LikeOperationSafetyAssertionBase is LendingBaseAssertion {
    ILendingProtectionSuite internal immutable SUITE;

    constructor(ILendingProtectionSuite suite_) {
        SUITE = suite_;
    }

    function _suite() internal view override returns (ILendingProtectionSuite) {
        return SUITE;
    }
}
