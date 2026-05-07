// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract OwnerChangeAssertion is Assertion {
    bytes32 internal constant OWNER_SLOT = bytes32(uint256(0));
    bytes32 internal constant ADMIN_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionOwnerChange.selector);
        registerTxEndTrigger(this.assertionAdminChange.selector);
    }

    /// @notice Checks that the owner slot is unchanged across the transaction.
    function assertionOwnerChange() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        address preOwner = _loadAddressAt(adopter, OWNER_SLOT, preFork);
        address postOwner = _loadAddressAt(adopter, OWNER_SLOT, postFork);

        require(preOwner == postOwner, "Owner changed");
    }

    /// @notice Checks that the admin slot is unchanged across the transaction.
    function assertionAdminChange() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        address preAdmin = _loadAddressAt(adopter, ADMIN_SLOT, preFork);
        address postAdmin = _loadAddressAt(adopter, ADMIN_SLOT, postFork);

        require(preAdmin == postAdmin, "Admin changed");
    }

    function _loadAddressAt(address target, bytes32 slot, PhEvm.ForkId memory fork) internal view returns (address) {
        return address(uint160(uint256(ph.loadStateAt(target, slot, fork))));
    }
}
