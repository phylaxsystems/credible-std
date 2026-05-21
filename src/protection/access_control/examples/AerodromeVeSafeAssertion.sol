// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {AerodromeVeSafeHelpers} from "./AerodromeVeSafeHelpers.sol";

/// @title AerodromeVeSafeAssertion
/// @author Phylax Systems
/// @notice Protects an Aerodrome governance Safe from veAERO custody and voting-power side effects.
/// - Denies veAERO ERC-721 approval and transfer events inside the Safe transaction.
/// - Denies veAERO delegation changes, which can redirect governance power without moving custody.
/// - Denies direct or nested calls to veAERO, Voter, and governor voting selectors that a treasury Safe
///   should not sign as part of routine administration.
contract AerodromeVeSafeAssertion is AerodromeVeSafeHelpers {
    constructor(address safe_, address ve_, address voter_, address protocolGovernor_, address epochGovernor_)
        AerodromeVeSafeHelpers(safe_, ve_, voter_, protocolGovernor_, epochGovernor_)
    {}

    /// @notice Registers Safe-level transaction-end guards for veAERO governance side effects.
    function triggers() external view override {
        registerTxEndTrigger(this.assertNoVeAeroApprovalOrTransferLogs.selector);
        registerTxEndTrigger(this.assertNoVeAeroDelegationChanges.selector);
        registerTxEndTrigger(this.assertNoVeAeroCustodyOrVotingPowerCalls.selector);
        registerTxEndTrigger(this.assertNoGovernorVotesFromSafe.selector);
    }

    /// @notice Checks a Safe transaction did not emit veAERO custody or approval logs.
    /// @dev A failure means the Safe transaction approved an operator, set approval-for-all, minted,
    ///      burned, received, or transferred a veAERO NFT. This intentionally treats all veAERO
    ///      ERC-721 movement in the Safe transaction as suspicious, not only movements from the Safe.
    function assertNoVeAeroApprovalOrTransferLogs() external {
        _requireConfiguredSafeIsAdopter();

        PhEvm.Log[] memory logs = ph.getLogs();
        _requireNoEvent(logs, VE, ERC721_APPROVAL_EVENT_SIGNATURE, "AerodromeVeSafe: veAERO Approval emitted");
        _requireNoEvent(
            logs, VE, ERC721_APPROVAL_FOR_ALL_EVENT_SIGNATURE, "AerodromeVeSafe: veAERO ApprovalForAll emitted"
        );
        _requireNoEvent(logs, VE, ERC721_TRANSFER_EVENT_SIGNATURE, "AerodromeVeSafe: veAERO Transfer emitted");
    }

    /// @notice Checks a Safe transaction did not delegate or undelegate veAERO voting power.
    /// @dev A failure means voting power moved between token IDs without a veNFT transfer. This catches
    ///      governance-control changes such as `delegate()` and relayed `delegateBySig()` execution.
    function assertNoVeAeroDelegationChanges() external {
        _requireConfiguredSafeIsAdopter();

        PhEvm.Log[] memory logs = ph.getLogs();
        _requireNoEvent(logs, VE, DELEGATE_CHANGED_EVENT_SIGNATURE, "AerodromeVeSafe: veAERO delegation changed");
    }

    /// @notice Checks a Safe transaction avoided veAERO custody, voting-power, and Voter vote selectors.
    /// @dev A failure means the Safe made a successful direct or nested call to a selector that can move
    ///      veNFT custody, mutate managed-NFT placement, change permanent/delegated power, or vote/reset.
    function assertNoVeAeroCustodyOrVotingPowerCalls() external view {
        _requireConfiguredSafeIsAdopter();

        _requireNoVeCustodyCalls();
        _requireNoVeVotingPowerCalls();
        _requireNoVoterVotingPowerCalls();
    }

    /// @notice Checks a Safe transaction did not cast token-id votes through configured governors.
    /// @dev A failure means the Safe itself cast, or successfully submitted, a ProtocolGovernor or
    ///      EpochGovernor vote path. Passing `address(0)` for a governor disables that governor check.
    function assertNoGovernorVotesFromSafe() external {
        _requireConfiguredSafeIsAdopter();

        PhEvm.Log[] memory logs = ph.getLogs();
        _requireNoSafeGovernorVote(logs, PROTOCOL_GOVERNOR);
        _requireNoSafeGovernorVote(logs, EPOCH_GOVERNOR);
        _requireNoGovernorVoteCalls(PROTOCOL_GOVERNOR);
        _requireNoGovernorVoteCalls(EPOCH_GOVERNOR);
    }
}
