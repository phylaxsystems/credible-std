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
///      The invariant: every locked-token unit that leaves the lockbox in a transaction must be
///      released *inside* a successful `lzReceive` invoked by the configured endpoint, and only up
///      to the amount the verified message itself authorizes. We do not check for the mere
///      presence of such a call — that would let an attacker drain the lockbox alongside any
///      unrelated (or even reverted) bridge-in. Instead we reconcile the gross outflow of the
///      locked token against a credit derived per verified receive:
///      `grossOutflow <= Σ min(messageAuthorizedAmount, amountReleasedWithinTheCall)`.
///      The message amount caps the credit, so a faulty or maliciously upgraded adapter that
///      releases more than the remote burn authorized still trips; the in-call release floor
///      gates success (a reverted `lzReceive` commits no logs and credits nothing). This blocks
///      the "becoming Kelp" failure mode (locked backing drained via compromised owner/upgrade,
///      stale approval, or faulty path so remote cUSD is left unbacked) even when the drain rides
///      in the same transaction as honest traffic.
contract CapOFTLockboxBackingAssertion is Assertion {
    /// @dev `Transfer(address,address,uint256)` topic0.
    bytes32 internal constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");

    /// @dev Rolling window for the outflow watcher and its (low) trip threshold in bps. Any
    ///      material release of locked cUSD fires the check; the assertion then validates it.
    uint256 internal constant WINDOW = 1 hours;
    uint256 internal constant WATCH_TRIGGER_BPS = 1;

    /// @notice The canonical token locked by the adapter (cUSD on the home chain).
    address internal immutable LOCKED_TOKEN;

    /// @notice The trusted LayerZero endpoint authorized to drive `lzReceive`.
    address internal immutable ENDPOINT;

    /// @notice Conversion rate from OFT shared-decimal units to locked-token local units,
    ///         i.e. `10 ** (localDecimals - sharedDecimals)` (1e12 for an 18-decimal token with
    ///         LayerZero's default 6 shared decimals).
    uint256 internal immutable DECIMAL_CONVERSION_RATE;

    constructor(address lockedToken_, address endpoint_, uint256 decimalConversionRate_) {
        LOCKED_TOKEN = lockedToken_;
        ENDPOINT = endpoint_;
        DECIMAL_CONVERSION_RATE = decimalConversionRate_;
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    function triggers() external view override {
        watchCumulativeOutflow(LOCKED_TOKEN, WATCH_TRIGGER_BPS, WINDOW, this.assertReleaseOnlyOnReceive.selector);
    }

    /// @notice Locked cUSD may only leave the lockbox via a verified endpoint `lzReceive`, and only
    ///         up to the amount those receives actually release.
    /// @dev Triggered when locked cUSD flows out of the adopter. Compares the gross amount of the
    ///      locked token transferred out of the lockbox this transaction against the amount
    ///      transferred out *within* successful endpoint-driven `lzReceive` calls. Any excess —
    ///      an unauthorized drain, or a drain riding alongside a legitimate (or reverted) bridge-in
    ///      — is unbacked and reverts.
    function assertReleaseOnlyOnReceive() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == LOCKED_TOKEN, "CapLockbox: unwatched token");

        address lockbox = ph.getAssertionAdopter();
        uint256 released = _grossOutflow(lockbox);
        uint256 credited = _creditedByVerifiedReceives(lockbox);

        require(released <= credited, "CapLockbox: locked cUSD released beyond verified receives");
    }

    /// @notice Total locked-token units transferred out of the lockbox during this transaction.
    function _grossOutflow(address lockbox) internal view returns (uint256 outflow) {
        PhEvm.Erc20TransferData[] memory transfers = ph.getErc20Transfers(LOCKED_TOKEN, _postTx());
        for (uint256 i; i < transfers.length; ++i) {
            if (transfers[i].from == lockbox) outflow += transfers[i].value;
        }
    }

    /// @notice Locked-token units authorized for release by successful endpoint-driven
    ///         `lzReceive` calls.
    /// @dev Per endpoint-driven `lzReceive`, credits `min(messageAuthorizedAmount,
    ///      amountReleasedWithinTheCall)`. The message amount — decoded from the verified OFT
    ///      payload, the same value the remote chain burned — is the cap, so a faulty or upgraded
    ///      adapter releasing more than authorized is not laundered by its own transfer logs. The
    ///      in-call release floor gates success: a reverted `lzReceive` commits no logs, so its
    ///      rolled-back release contributes nothing.
    function _creditedByVerifiedReceives(address lockbox) internal view returns (uint256 credited) {
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(lockbox, ILayerZeroReceiverLike.lzReceive.selector);

        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: LOCKED_TOKEN, signature: TRANSFER_SIG});

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].caller != ENDPOINT) continue;

            uint256 authorized = _messageAmount(calls[i].input);
            if (authorized == 0) continue;

            uint256 releasedInCall;
            PhEvm.Log[] memory logs = ph.getLogsForCall(query, calls[i].id);
            for (uint256 j; j < logs.length; ++j) {
                // topics: [sig, from, to]; data: amount. Count only releases out of the lockbox.
                if (logs[j].topics.length == 3 && _topicAddress(logs[j].topics[1]) == lockbox) {
                    releasedInCall += abi.decode(logs[j].data, (uint256));
                }
            }

            credited += releasedInCall < authorized ? releasedInCall : authorized;
        }
    }

    /// @notice Amount of locked token the verified message authorizes for release, in local units.
    /// @dev `input` is the `lzReceive` calldata without the 4-byte selector (`getAllCallInputs`
    ///      strips it), so the arguments decode directly. The OFT codec packs the message as
    ///      `sendTo` (bytes32) at [0, 32) followed by `amountSD` (uint64, shared decimals) at
    ///      [32, 40). A message too short to carry an amount authorizes nothing.
    function _messageAmount(bytes memory input) internal view returns (uint256) {
        (,, bytes memory message,,) =
            abi.decode(input, (ILayerZeroReceiverLike.Origin, bytes32, bytes, address, bytes));
        if (message.length < 40) return 0;

        uint64 amountSD;
        assembly {
            // Skip the 32-byte length word and the 32-byte `sendTo`; amountSD is the top 8 bytes.
            amountSD := shr(192, mload(add(message, 64)))
        }
        return uint256(amountSD) * DECIMAL_CONVERSION_RATE;
    }

    function _topicAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
