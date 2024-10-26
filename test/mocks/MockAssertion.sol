// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../src/Assertion.sol";

contract MockAssertion is Assertion {
    function fnSelectors() external override pure returns (Trigger[] memory) {
        Trigger[] memory triggers = new Trigger[](1);
        triggers[0] = Trigger({triggerType: TriggerType.STORAGE, fnSelector: this.assertionTrue.selector});
        return triggers;
    }

    function assertionTrue() public pure returns(bool){
        return true;
    }
}