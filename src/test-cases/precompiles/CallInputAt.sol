// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestCallInputAt is Assertion {
    constructor() payable {}

    function callInputAt() external view {
        PhEvm.CallInputs[] memory callInputs = ph.getCallInputs(address(TARGET), Target.writeStorage.selector);
        require(callInputs.length == 2, "callInputs.length != 2");

        bytes memory firstInput = ph.callinputAt(callInputs[0].id);
        bytes memory secondInput = ph.callinputAt(callInputs[1].id);

        require(
            keccak256(firstInput) == keccak256(abi.encodeWithSelector(Target.writeStorage.selector, uint256(1))),
            "unexpected first calldata"
        );
        require(
            keccak256(secondInput) == keccak256(abi.encodeWithSelector(Target.writeStorage.selector, uint256(2))),
            "unexpected second calldata"
        );
    }

    function emptyCalldataReturnsEmptyBytes() external view {
        PhEvm.CallInputs[] memory emptyCalls = ph.getCallInputs(address(TARGET), bytes4(0));
        require(emptyCalls.length == 1, "emptyCalls.length != 1");
        require(ph.callinputAt(emptyCalls[0].id).length == 0, "empty calldata should return empty bytes");
    }

    function triggers() external view override {
        registerCallTrigger(this.callInputAt.selector);
        registerCallTrigger(this.emptyCalldataReturnsEmptyBytes.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
        TARGET.writeStorage(2);

        (bool success,) = address(TARGET).call("");
        require(success, "call failed");
    }
}
