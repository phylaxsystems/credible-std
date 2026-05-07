// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ERC4626AssetsSharesAssertion is Assertion {
    bytes32 internal constant TOTAL_ASSETS_SLOT = bytes32(uint256(0));
    bytes32 internal constant TOTAL_SUPPLY_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionAssetsShares.selector);
    }

    /// @notice Checks that stored total assets are sufficient to back stored total shares.
    function assertionAssetsShares() external view {
        address vault = ph.getAssertionAdopter();
        PhEvm.ForkId memory postFork = _postTx();

        uint256 totalAssets = uint256(ph.loadStateAt(vault, TOTAL_ASSETS_SLOT, postFork));
        uint256 totalSupply = uint256(ph.loadStateAt(vault, TOTAL_SUPPLY_SLOT, postFork));

        require(totalAssets >= totalSupply, "Not enough assets to back all shares");
    }
}
