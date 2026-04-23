// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {RoycoKernelBaseAssertion} from "../RoycoKernelBaseAssertion.sol";
import {RoycoKernelCumulativeFlowAssertion} from "../RoycoKernelCumulativeFlowAssertion.sol";

/// @title RoycoKernelAssertion
/// @author Phylax Systems
/// @notice Example Royco assertion bundle that installs cumulative inflow and outflow breakers
///         on the kernel's custody balances for the senior and junior tranche assets.
/// @dev Adopt this assertion on the Royco kernel, not on either tranche ERC-20.
contract RoycoKernelAssertion is RoycoKernelCumulativeFlowAssertion {
    constructor(
        address kernel_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_,
        uint256 inflowThresholdBps_,
        uint256 inflowWindowDuration_
    )
        RoycoKernelBaseAssertion(kernel_)
        RoycoKernelCumulativeFlowAssertion(
            outflowThresholdBps_, outflowWindowDuration_, inflowThresholdBps_, inflowWindowDuration_
        )
    {}

    function triggers() external view override {
        _registerCumulativeFlowTriggers();
    }
}
