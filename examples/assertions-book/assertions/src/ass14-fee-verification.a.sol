// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract AmmFeeVerificationAssertion is Assertion {
    bytes32 internal constant FEE_SLOT = bytes32(uint256(1));
    bytes32 internal constant STABLE_SLOT = bytes32(uint256(2));

    uint256 private constant STABLE_POOL_FEE_1 = 1;
    uint256 private constant STABLE_POOL_FEE_2 = 15;
    uint256 private constant NON_STABLE_POOL_FEE_1 = 25;
    uint256 private constant NON_STABLE_POOL_FEE_2 = 30;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertFeeVerification.selector);
    }

    /// @notice Checks that the post-transaction fee is one of the allowed values.
    function assertFeeVerification() external view {
        address pool = ph.getAssertionAdopter();
        PhEvm.ForkId memory postFork = _postTx();

        bool isStable = uint256(ph.loadStateAt(pool, STABLE_SLOT, postFork)) != 0;
        uint256 newFee = uint256(ph.loadStateAt(pool, FEE_SLOT, postFork));
        bool isAllowed = isStable
            ? (newFee == STABLE_POOL_FEE_1 || newFee == STABLE_POOL_FEE_2)
            : (newFee == NON_STABLE_POOL_FEE_1 || newFee == NON_STABLE_POOL_FEE_2);

        require(isAllowed, "Fee change to unauthorized value");
    }
}
