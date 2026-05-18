// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ImplementationChangeAssertion is Assertion {
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(0));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.implementationChange.selector);
    }

    /// @notice Checks that the implementation slot is unchanged across the transaction.
    function implementationChange() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        address preImpl = _loadAddressAt(adopter, IMPLEMENTATION_SLOT, preFork);
        address postImpl = _loadAddressAt(adopter, IMPLEMENTATION_SLOT, postFork);

        require(preImpl == postImpl, "Implementation changed");
    }

    function _loadAddressAt(address target, bytes32 slot, PhEvm.ForkId memory fork) internal view returns (address) {
        return address(uint160(uint256(ph.loadStateAt(target, slot, fork))));
    }
}
