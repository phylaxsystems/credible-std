// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract LendingHealthFactorAssertion is Assertion {
    bytes32 internal constant HEALTH_FACTOR_SLOT = bytes32(uint256(0));
    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertionOperationSafety.selector, IMorpho.supply.selector);
        registerFnCallTrigger(this.assertionOperationSafety.selector, IMorpho.borrow.selector);
        registerFnCallTrigger(this.assertionOperationSafety.selector, IMorpho.withdraw.selector);
        registerFnCallTrigger(this.assertionOperationSafety.selector, IMorpho.repay.selector);
    }

    /// @notice Checks that the touched account remains healthy after a lending operation.
    function assertionOperationSafety() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory postCall = PhEvm.ForkId({forkType: 3, callIndex: ctx.callEnd});
        (uint256 marketId,) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (uint256, uint256));
        address account = _matchingCaller(ctx.selector);
        bytes32 healthSlot = _healthFactorSlot(marketId, account);
        uint256 healthFactor = uint256(ph.loadStateAt(ph.getAssertionAdopter(), healthSlot, postCall));

        require(healthFactor >= MIN_HEALTH_FACTOR, "Operation resulted in unhealthy position");
    }

    function _matchingCaller(bytes4 selector) internal view returns (address) {
        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(ph.getAssertionAdopter(), selector, _successfulCalls(), 1);
        require(calls.length == 1, "missing triggered call");
        return calls[0].caller;
    }

    function _successfulCalls() internal pure returns (PhEvm.CallFilter memory filter) {
        filter.callType = 1;
        filter.successOnly = true;
    }

    function _healthFactorSlot(uint256 marketId, address account) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, keccak256(abi.encode(marketId, HEALTH_FACTOR_SLOT))));
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory) {
        bytes memory stripped = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; i++) {
            stripped[i - 4] = data[i];
        }
        return stripped;
    }
}

interface IMorpho {
    function supply(uint256 marketId, uint256 amount) external;
    function borrow(uint256 marketId, uint256 amount) external;
    function withdraw(uint256 marketId, uint256 amount) external;
    function repay(uint256 marketId, uint256 amount) external;
}
