// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract PositionSumAssertion is Assertion {
    bytes32 internal constant TOTAL_SUPPLY_SLOT = bytes32(uint256(0));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertionPositionsSum.selector, ILending.deposit.selector);
    }

    /// @notice Checks that a deposit call increases stored total supply by the deposited amount.
    function assertionPositionsSum() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preCall = PhEvm.ForkId({forkType: 2, callIndex: ctx.callStart});
        PhEvm.ForkId memory postCall = PhEvm.ForkId({forkType: 3, callIndex: ctx.callEnd});

        uint256 preTotalSupply = uint256(ph.loadStateAt(adopter, TOTAL_SUPPLY_SLOT, preCall));
        uint256 postTotalSupply = uint256(ph.loadStateAt(adopter, TOTAL_SUPPLY_SLOT, postCall));
        (, uint256 amount) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256));

        require(postTotalSupply == preTotalSupply + amount, "Positions sum does not match total supply");
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory) {
        bytes memory stripped = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; i++) {
            stripped[i - 4] = data[i];
        }
        return stripped;
    }
}

interface ILending {
    function deposit(address user, uint256 amount) external;
}
