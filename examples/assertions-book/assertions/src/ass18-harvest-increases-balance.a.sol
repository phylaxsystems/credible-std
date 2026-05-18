// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract BeefyHarvestAssertion is Assertion {
    bytes32 internal constant BALANCE_SLOT = bytes32(uint256(0));
    bytes32 internal constant PRICE_PER_SHARE_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertionHarvestIncreasesBalance.selector, IBeefyVault.harvest.selector);
    }

    /// @notice Checks that a harvest does not reduce vault balance or price per share.
    function assertionHarvestIncreasesBalance() external view {
        address vault = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.ForkId memory preCall = PhEvm.ForkId({forkType: 2, callIndex: ctx.callStart});
        PhEvm.ForkId memory postCall = PhEvm.ForkId({forkType: 3, callIndex: ctx.callEnd});

        uint256 preBalance = uint256(ph.loadStateAt(vault, BALANCE_SLOT, preCall));
        uint256 postBalance = uint256(ph.loadStateAt(vault, BALANCE_SLOT, postCall));
        uint256 prePricePerShare = uint256(ph.loadStateAt(vault, PRICE_PER_SHARE_SLOT, preCall));
        uint256 postPricePerShare = uint256(ph.loadStateAt(vault, PRICE_PER_SHARE_SLOT, postCall));

        require(postBalance >= preBalance, "Harvest decreased balance");
        require(postPricePerShare >= prePricePerShare, "Price per share decreased after harvest");
    }
}

interface IBeefyVault {
    function harvest(bool badHarvest) external;
}
