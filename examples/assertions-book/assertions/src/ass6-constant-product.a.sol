// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ConstantProductAssertion is Assertion {
    bytes32 internal constant RESERVE0_SLOT = bytes32(uint256(0));
    bytes32 internal constant RESERVE1_SLOT = bytes32(uint256(1));

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertionConstantProduct.selector);
    }

    /// @notice Checks that the pool's stored reserve product is not reduced by the transaction.
    function assertionConstantProduct() external view {
        address pool = ph.getAssertionAdopter();
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        uint256 reserve0Pre = uint256(ph.loadStateAt(pool, RESERVE0_SLOT, preFork));
        uint256 reserve1Pre = uint256(ph.loadStateAt(pool, RESERVE1_SLOT, preFork));
        uint256 reserve0Post = uint256(ph.loadStateAt(pool, RESERVE0_SLOT, postFork));
        uint256 reserve1Post = uint256(ph.loadStateAt(pool, RESERVE1_SLOT, postFork));

        require(reserve0Post * reserve1Post >= reserve0Pre * reserve1Pre, "Constant product invariant reduced");
    }
}
