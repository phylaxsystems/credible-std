// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract TimelockVerificationAssertion is Assertion {
    bytes32 internal constant TIMELOCK_DELAY_SLOT = bytes32(uint256(0));
    bytes32 internal constant TIMELOCK_ACTIVE_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionTimelock.selector);
    }

    /// @notice Checks that an activated timelock uses a bounded delay.
    function assertionTimelock() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        bool preActive = uint256(ph.loadStateAt(adopter, TIMELOCK_ACTIVE_SLOT, preFork)) != 0;
        if (preActive) {
            return;
        }

        bool postActive = uint256(ph.loadStateAt(adopter, TIMELOCK_ACTIVE_SLOT, postFork)) != 0;
        if (postActive) {
            uint256 delay = uint256(ph.loadStateAt(adopter, TIMELOCK_DELAY_SLOT, postFork));

            require(delay >= 1 days && delay <= 2 weeks, "Timelock parameters invalid");
        }
    }
}
