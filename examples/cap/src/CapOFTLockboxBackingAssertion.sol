// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {ILayerZeroReceiverLike} from "./CapOFTLockboxInterfaces.sol";

/// @title CapOFTLockboxBackingAssertion
/// @author Phylax Systems
/// @notice Keeps Cap's cross-chain cUSD honest: locked collateral can only leave the home-chain
///         lockbox through a verified LayerZero receive (a matching remote burn).
/// @dev Deploy against the `OFTLockbox` (a LayerZero `OFTAdapter`) on the chain that holds the
///      canonical cUSD. Remote `L2Token` supply is only minted when cUSD is locked here, and the
///      adapter releases that locked cUSD exclusively inside `lzReceive`, called by the trusted
///      endpoint after the source chain burned an equal amount.
///
///      The invariant: any outflow of the locked token from the lockbox must coincide with a
///      successful `lzReceive` invoked by the configured endpoint. This blocks the "becoming Kelp"
///      failure mode — locked backing being drained (compromised owner/upgrade, stale approval,
///      faulty path) so remote cUSD is left unbacked — even when no single contract `require`
///      would catch it. The cumulative-outflow trigger fires on any release, so legitimate
///      bridge-ins pass (their `lzReceive` is present) while unauthorized drains revert.
contract CapOFTLockboxBackingAssertion is Assertion {
    /// @dev Rolling window for the outflow watcher and its (low) trip threshold in bps. Any
    ///      material release of locked cUSD fires the check; the assertion then validates it.
    uint256 internal constant WINDOW = 1 hours;
    uint256 internal constant WATCH_TRIGGER_BPS = 1;

    /// @notice The canonical token locked by the adapter (cUSD on the home chain).
    address internal immutable LOCKED_TOKEN;

    /// @notice The trusted LayerZero endpoint authorized to drive `lzReceive`.
    address internal immutable ENDPOINT;

    constructor(address lockedToken_, address endpoint_) {
        LOCKED_TOKEN = lockedToken_;
        ENDPOINT = endpoint_;
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    function triggers() external view override {
        watchCumulativeOutflow(LOCKED_TOKEN, WATCH_TRIGGER_BPS, WINDOW, this.assertReleaseOnlyOnReceive.selector);
    }

    /// @notice Locked cUSD may only leave the lockbox via a verified endpoint `lzReceive`.
    /// @dev Triggered when locked cUSD flows out of the adopter. Fails unless the transaction
    ///      contains a successful `lzReceive` call into the lockbox made by the trusted endpoint,
    ///      i.e. the release settles a verified remote burn rather than an unauthorized drain.
    function assertReleaseOnlyOnReceive() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == LOCKED_TOKEN, "CapLockbox: unwatched token");

        if (!_endpointReceivePresent()) {
            revert("CapLockbox: locked cUSD released outside bridge receive");
        }
    }

    /// @notice True when the trusted endpoint invoked `lzReceive` on the lockbox this transaction.
    function _endpointReceivePresent() internal view returns (bool) {
        PhEvm.CallInputs[] memory calls =
            ph.getAllCallInputs(ph.getAssertionAdopter(), ILayerZeroReceiverLike.lzReceive.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].caller == ENDPOINT) return true;
        }

        return false;
    }
}
