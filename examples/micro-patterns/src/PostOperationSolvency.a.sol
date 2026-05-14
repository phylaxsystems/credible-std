// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IRiskEngine {
    function borrow(uint256 marketId, uint256 amount) external;
    function withdraw(uint256 marketId, uint256 amount) external;
    function liquidate(uint256 marketId, address account) external;
    function healthFactor(address account, uint256 marketId) external view returns (uint256);
}

/// @notice Risk-increasing operations must leave the touched account solvent; liquidations must improve it.
/// @dev Protects against bad post-state after lending/perp mutations:
///      - borrow or withdraw succeeding while the caller becomes undercollateralized;
///      - liquidation taking collateral or repaying debt without improving account health;
///      - liquidation leaving the account below the protocol's minimum healthy threshold.
contract PostOperationSolvencyAssertion is Assertion {
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertPostOperationSolvency.selector, IRiskEngine.borrow.selector);
        registerFnCallTrigger(this.assertPostOperationSolvency.selector, IRiskEngine.withdraw.selector);
        registerFnCallTrigger(this.assertLiquidationImprovesHealth.selector, IRiskEngine.liquidate.selector);
    }

    function assertPostOperationSolvency() external view {
        address protocol = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory ctx = ph.context();
        (uint256 marketId,) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (uint256, uint256));
        address account = _triggerCaller(protocol, ctx);

        uint256 postHealth = _healthAt(protocol, account, marketId, _postCall(ctx.callEnd));

        // Failure scenario: a risk-increasing operation succeeds even though the account is insolvent after it.
        require(postHealth >= MIN_HEALTH_FACTOR, "operation left account unhealthy");
    }

    function assertLiquidationImprovesHealth() external view {
        address protocol = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory ctx = ph.context();
        (uint256 marketId, address account) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (uint256, address));

        uint256 preHealth = _healthAt(protocol, account, marketId, _preCall(ctx.callStart));
        uint256 postHealth = _healthAt(protocol, account, marketId, _postCall(ctx.callEnd));

        // Failure scenario: liquidation executes but does not actually reduce the target account's risk.
        require(postHealth > preHealth, "liquidation did not improve health");

        // Failure scenario: liquidation improves the position but still leaves bad debt in place.
        require(postHealth >= MIN_HEALTH_FACTOR, "liquidation left account unhealthy");
    }

    function _healthAt(address protocol, address account, uint256 marketId, PhEvm.ForkId memory fork)
        private
        view
        returns (uint256)
    {
        return _readUintAt(protocol, abi.encodeCall(IRiskEngine.healthFactor, (account, marketId)), fork);
    }

    function _triggerCaller(address target, PhEvm.TriggerContext memory ctx) private view returns (address) {
        PhEvm.TriggerCall[] memory calls = _matchingCalls(target, ctx.selector, 16);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].callId == ctx.callStart) return calls[i].caller;
        }
        revert("trigger call not found");
    }

    function _stripSelector(bytes memory input) private pure returns (bytes memory args) {
        require(input.length >= 4, "input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) args[i] = input[i + 4];
    }
}
