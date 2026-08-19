// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title LighterBatchProofAssertion
/// @notice Independently verifies Lighter's submitted gnark PLONK batch proof.
/// @dev This experimental assertion is deliberately bound to one L1 proxy and
///      one compiled-in verifier key. It validates the matching call context,
///      then checks the batch commitment and proof extracted from verifyBatch.
contract LighterBatchProofAssertion is Assertion {
    bytes4 internal constant VERIFY_BATCH_SELECTOR = 0x23ff50e1;
    bytes32 internal constant LIGHTER_GNARK_PLONK_VK_ID =
        0x7856ff107f35077ed23aa1cbd1a4ec95204585dc675e0d3632231c49e48109d0;

    address public immutable lighterProxy;

    /// @notice `StoredBatchInfo` has eleven static ABI words in the pinned Lighter ABI.
    /// @dev Words are retained verbatim because this assertion only needs the final commitment.
    struct StoredBatchInfo {
        bytes32[11] words;
    }

    constructor(address lighterProxy_) {
        require(lighterProxy_ != address(0), "LighterBatchProof: zero proxy");
        lighterProxy = lighterProxy_;
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertBatchProof.selector, VERIFY_BATCH_SELECTOR);
    }

    /// @notice Verifies the proof submitted with the exact triggering batch.
    /// @dev Rejects calls from any adopter other than the configured Lighter proxy,
    ///      malformed verifyBatch calldata, and algebraically invalid proofs.
    function assertBatchProof() external view {
        require(ph.getAssertionAdopter() == lighterProxy, "LighterBatchProof: wrong adopter");
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        require(input.length >= 4, "LighterBatchProof: malformed calldata");
        require(bytes4(input) == VERIFY_BATCH_SELECTOR, "LighterBatchProof: wrong selector");

        (StoredBatchInfo memory batch, bytes memory proof) = abi.decode(_withoutSelector(input), (StoredBatchInfo, bytes));
        require(
            ph.verifyGnarkPlonkProof(proof, batch.words[10], LIGHTER_GNARK_PLONK_VK_ID),
            "LighterBatchProof: invalid proof"
        );
    }

    function _withoutSelector(bytes memory input) private pure returns (bytes memory args) {
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) args[i] = input[i + 4];
    }
}
