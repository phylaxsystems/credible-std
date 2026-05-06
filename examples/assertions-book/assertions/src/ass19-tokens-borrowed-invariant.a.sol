// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract TokensBorrowedInvariant is Assertion {
    bytes32 internal constant TOTAL_SUPPLY_SLOT = bytes32(uint256(0));
    bytes32 internal constant TOTAL_BORROW_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertBorrowedInvariant.selector);
    }

    /// @notice Checks that total supplied assets cover total borrowed assets after the transaction.
    function assertBorrowedInvariant() external view {
        address market = ph.getAssertionAdopter();
        PhEvm.ForkId memory postFork = _postTx();

        uint256 totalSupplyAsset = uint256(ph.loadStateAt(market, TOTAL_SUPPLY_SLOT, postFork));
        uint256 totalBorrowedAsset = uint256(ph.loadStateAt(market, TOTAL_BORROW_SLOT, postFork));

        require(
            totalSupplyAsset >= totalBorrowedAsset,
            "INVARIANT VIOLATION: Total supply of assets is less than total borrowed assets"
        );
    }
}
