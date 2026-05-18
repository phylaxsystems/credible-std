// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ERC4626DepositWithdrawAssertion is Assertion {
    bytes32 internal constant TOTAL_ASSETS_SLOT = bytes32(uint256(0));
    bytes32 internal constant TOTAL_SUPPLY_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertDepositPreservesSharePrice.selector, IERC4626.deposit.selector);
        registerFnCallTrigger(this.assertWithdrawPreservesSharePrice.selector, IERC4626.withdraw.selector);
    }

    /// @notice Checks that a deposit does not dilute existing shares.
    function assertDepositPreservesSharePrice() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _assertSharePriceNotReduced(ctx.callStart, ctx.callEnd, "ERC4626: deposit diluted shares");
    }

    /// @notice Checks that a withdrawal does not dilute remaining shares.
    function assertWithdrawPreservesSharePrice() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _assertSharePriceNotReduced(ctx.callStart, ctx.callEnd, "ERC4626: withdrawal diluted shares");
    }

    function _assertSharePriceNotReduced(uint256 callStart, uint256 callEnd, string memory reason) internal view {
        address vault = ph.getAssertionAdopter();
        PhEvm.ForkId memory preCall = PhEvm.ForkId({forkType: 2, callIndex: callStart});
        PhEvm.ForkId memory postCall = PhEvm.ForkId({forkType: 3, callIndex: callEnd});

        uint256 preAssets = uint256(ph.loadStateAt(vault, TOTAL_ASSETS_SLOT, preCall));
        uint256 preSupply = uint256(ph.loadStateAt(vault, TOTAL_SUPPLY_SLOT, preCall));
        uint256 postAssets = uint256(ph.loadStateAt(vault, TOTAL_ASSETS_SLOT, postCall));
        uint256 postSupply = uint256(ph.loadStateAt(vault, TOTAL_SUPPLY_SLOT, postCall));

        if (preSupply == 0 || postSupply == 0) {
            return;
        }

        require(postAssets * preSupply >= preAssets * postSupply, reason);
    }
}

interface IERC4626 {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
}
