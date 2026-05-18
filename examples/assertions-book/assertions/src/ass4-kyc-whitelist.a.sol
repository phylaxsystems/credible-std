// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {OnlyAccreditedCanMint} from "../../src/ass4-only-accredited-can-mint.sol";
import {AccreditedInvestorRegistry} from "../../src/AccreditedInvestorRegistry.sol";

contract OnlyAccreditedCanMintAssertion is Assertion {
    AccreditedInvestorRegistry public immutable registry;

    constructor(address registry_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
        registry = AccreditedInvestorRegistry(registry_);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertOnlyAccreditedMint.selector, OnlyAccreditedCanMint.mint.selector);
        registerFnCallTrigger(this.assertOnlyAccreditedTransfer.selector, OnlyAccreditedCanMint.transfer.selector);
    }

    /// @notice Checks that the caller of `mint` is accredited.
    function assertOnlyAccreditedMint() external view {
        _assertMatchingCallersAccredited(OnlyAccreditedCanMint.mint.selector);
    }

    /// @notice Checks that the caller of `transfer` is accredited.
    function assertOnlyAccreditedTransfer() external view {
        _assertMatchingCallersAccredited(OnlyAccreditedCanMint.transfer.selector);
    }

    function _assertMatchingCallersAccredited(bytes4 selector) internal view {
        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(ph.getAssertionAdopter(), selector, _successfulCalls(), 32);
        for (uint256 i = 0; i < calls.length; i++) {
            require(registry.isAccredited(calls[i].caller), "caller is not accredited");
        }
    }

    function _successfulCalls() internal pure returns (PhEvm.CallFilter memory filter) {
        filter.callType = 1;
        filter.successOnly = true;
    }
}
