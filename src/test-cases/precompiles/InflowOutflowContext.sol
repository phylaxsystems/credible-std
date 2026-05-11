// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

/// @dev Verifies the inflow/outflow context precompiles return a zeroed struct when called
///      outside of their watchCumulative{Inflow,Outflow} trigger context. The non-zero
///      paths require a circuit-breaker fixture and are covered by protection-suite tests.
contract TestInflowOutflowContextOutsideTrigger is Assertion {
    constructor() payable {}

    function outflowContextOutsideTriggerIsZero() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == address(0), "outflow token must be zero outside trigger");
        require(ctx.cumulativeOutflow == 0, "outflow cumulative must be zero");
        require(ctx.absoluteOutflow == 0, "outflow absolute must be zero");
        require(ctx.currentBps == 0, "outflow bps must be zero");
        require(ctx.tvlSnapshot == 0, "outflow tvl must be zero");
        require(ctx.windowStart == 0, "outflow windowStart must be zero");
        require(ctx.windowEnd == 0, "outflow windowEnd must be zero");
    }

    function inflowContextOutsideTriggerIsZero() external view {
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ctx.token == address(0), "inflow token must be zero outside trigger");
        require(ctx.cumulativeInflow == 0, "inflow cumulative must be zero");
        require(ctx.absoluteInflow == 0, "inflow absolute must be zero");
        require(ctx.currentBps == 0, "inflow bps must be zero");
        require(ctx.tvlSnapshot == 0, "inflow tvl must be zero");
        require(ctx.windowStart == 0, "inflow windowStart must be zero");
        require(ctx.windowEnd == 0, "inflow windowEnd must be zero");
    }

    function triggers() external view override {
        registerCallTrigger(this.outflowContextOutsideTriggerIsZero.selector);
        registerCallTrigger(this.inflowContextOutsideTriggerIsZero.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
    }
}
