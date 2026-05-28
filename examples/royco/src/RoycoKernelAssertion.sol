// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {RoycoKernelHelpers} from "./RoycoHelpers.sol";
import {RoycoKernelAccountingAssertion} from "./RoycoKernelAccountingAssertion.sol";
import {RoycoKernelCumulativeFlowAssertion} from "./RoycoKernelCumulativeFlowAssertion.sol";

/// @title RoycoKernelAssertion
/// @author Phylax Systems
/// @notice Executive summary: this bundle watches Royco's kernel/accountant invariants that
///         should never be violated by a successful market operation. It enforces zero-sum NAV
///         accounting across tranches, blocks unhealthy perpetual states or coverage-breaking
///         flows, preserves recovery priority and JT-IL erasure rules, and adds inflow/outflow
///         circuit breakers on the kernel's custody balances.
/// @dev Adopt this assertion on the Royco kernel, not on either tranche ERC-20.
contract RoycoKernelAssertion is RoycoKernelAccountingAssertion, RoycoKernelCumulativeFlowAssertion {
    constructor(
        address kernel_,
        address accountant_,
        address seniorTranche_,
        address stAsset_,
        address juniorTranche_,
        address jtAsset_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_,
        uint256 inflowThresholdBps_,
        uint256 inflowWindowDuration_
    )
        RoycoKernelHelpers(kernel_, accountant_, seniorTranche_, stAsset_, juniorTranche_, jtAsset_)
        RoycoKernelCumulativeFlowAssertion(
            outflowThresholdBps_, outflowWindowDuration_, inflowThresholdBps_, inflowWindowDuration_
        )
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        _registerAccountingInvariantTriggers();
        _registerCumulativeFlowTriggers();
    }
}
