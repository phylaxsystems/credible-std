// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract EmergencyStateAssertion is Assertion {
    bytes32 internal constant PAUSED_SLOT = bytes32(uint256(0));
    bytes32 internal constant BALANCE_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionPanickedCanOnlyDecreaseBalance.selector);
    }

    /// @notice Checks that a paused protocol cannot increase its stored balance.
    function assertionPanickedCanOnlyDecreaseBalance() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        bool wasPaused = uint256(ph.loadStateAt(adopter, PAUSED_SLOT, preFork)) != 0;
        if (!wasPaused) {
            return;
        }

        uint256 preBalance = uint256(ph.loadStateAt(adopter, BALANCE_SLOT, preFork));
        uint256 postBalance = uint256(ph.loadStateAt(adopter, BALANCE_SLOT, postFork));

        require(postBalance <= preBalance, "Balance can only decrease when panicked");
    }
}
