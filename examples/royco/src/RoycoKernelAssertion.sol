// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {RoycoKernelHelpers} from "./RoycoHelpers.sol";
import {RoycoKernelAccountingAssertion} from "./RoycoKernelAccountingAssertion.sol";

/// @title RoycoKernelAssertion
/// @author Phylax Systems
/// @notice Executive summary: this bundle watches Royco's kernel/accountant invariants that
///         should never be violated by a successful market operation. It enforces zero-sum NAV
///         accounting across tranches, preserves the ordinary coverage floor, and checks the
///         protocol's self-liquidation deleveraging rule.
/// @dev Adopt this assertion on the Royco kernel, not on either tranche ERC-20.
contract RoycoKernelAssertion is RoycoKernelAccountingAssertion {
    constructor(
        address kernel_,
        address accountant_,
        address seniorTranche_,
        address stAsset_,
        address juniorTranche_,
        address jtAsset_
    )
        RoycoKernelHelpers(kernel_, accountant_, seniorTranche_, stAsset_, juniorTranche_, jtAsset_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        _registerAccountingInvariantTriggers();
    }
}
