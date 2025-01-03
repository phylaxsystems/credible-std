// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../src/Assertion.sol";

contract MockAssertion is Assertion {
    function fnSelectors() external pure override returns (bytes4[] memory assertions) {
        assertions = new bytes4[](1);
        assertions[0] = this.assertionTrue.selector;
    }

    function assertionTrue() public pure returns (bool) {
        return true;
    }
}
