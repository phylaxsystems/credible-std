// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestContext is Assertion {
    constructor() payable {}

    function checkContext() external view {
        PhEvm.TriggerContext memory ctx = ph.context();

        require(ctx.selector == Target.writeStorage.selector, "ctx.selector != writeStorage");
        require(ctx.callEnd >= ctx.callStart, "callEnd < callStart");

        bytes memory input = ph.callinputAt(ctx.callStart);
        require(
            keccak256(input) == keccak256(abi.encodeWithSelector(Target.writeStorage.selector, uint256(42))),
            "ctx.callStart input mismatch"
        );

        // PostCall fork at ctx.callEnd should reflect the write.
        bytes32 slot = bytes32(uint256(0));
        bytes32 post = ph.loadStateAt(address(TARGET), slot, _postCall(ctx.callEnd));
        require(post == bytes32(uint256(42)), "post-call value != 42");
    }

    function triggers() external view override {
        registerFnCallTrigger(this.checkContext.selector, Target.writeStorage.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(42);
    }
}
