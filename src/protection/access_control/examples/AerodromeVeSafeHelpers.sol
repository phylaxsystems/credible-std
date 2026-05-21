// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";

import {
    IAerodromeVeSafeVotingEscrowLike,
    IAerodromeVeSafeVoterLike,
    IAerodromeVeSafeGovernorLike
} from "./AerodromeVeSafeInterfaces.sol";

/// @title AerodromeVeSafeHelpers
/// @notice Shared log and call-trace guards for Safe-scoped veAERO governance assertions.
abstract contract AerodromeVeSafeHelpers is Assertion {
    bytes32 internal constant ERC721_TRANSFER_EVENT_SIGNATURE = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant ERC721_APPROVAL_EVENT_SIGNATURE = keccak256("Approval(address,address,uint256)");
    bytes32 internal constant ERC721_APPROVAL_FOR_ALL_EVENT_SIGNATURE =
        keccak256("ApprovalForAll(address,address,bool)");
    bytes32 internal constant DELEGATE_CHANGED_EVENT_SIGNATURE = keccak256("DelegateChanged(address,uint256,uint256)");
    bytes32 internal constant VOTE_CAST_EVENT_SIGNATURE =
        keccak256("VoteCast(address,uint256,uint256,uint8,uint256,string)");
    bytes32 internal constant VOTE_CAST_WITH_PARAMS_EVENT_SIGNATURE =
        keccak256("VoteCastWithParams(address,uint256,uint256,uint8,uint256,string,bytes)");

    bytes4 internal constant SAFE_TRANSFER_FROM_SELECTOR =
        bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
    bytes4 internal constant SAFE_TRANSFER_FROM_WITH_DATA_SELECTOR =
        bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));

    address internal immutable SAFE;
    address internal immutable VE;
    address internal immutable VOTER;
    address internal immutable PROTOCOL_GOVERNOR;
    address internal immutable EPOCH_GOVERNOR;

    constructor(address safe_, address ve_, address voter_, address protocolGovernor_, address epochGovernor_) {
        require(safe_ != address(0), "AerodromeVeSafe: zero safe");
        require(ve_ != address(0), "AerodromeVeSafe: zero veAERO");

        SAFE = safe_;
        VE = ve_;
        VOTER = voter_;
        PROTOCOL_GOVERNOR = protocolGovernor_;
        EPOCH_GOVERNOR = epochGovernor_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function _requireConfiguredSafeIsAdopter() internal view {
        require(ph.getAssertionAdopter() == SAFE, "AerodromeVeSafe: configured safe is not adopter");
    }

    function _requireNoEvent(PhEvm.Log[] memory logs, address emitter, bytes32 signature, string memory reason)
        internal
        pure
    {
        for (uint256 i; i < logs.length; ++i) {
            require(logs[i].emitter != emitter || !_hasSignature(logs[i], signature), reason);
        }
    }

    function _requireNoSafeGovernorVote(PhEvm.Log[] memory logs, address governor) internal view {
        if (governor == address(0)) return;

        bytes32 safeTopic = bytes32(uint256(uint160(SAFE)));
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != governor || logs[i].topics.length < 2 || logs[i].topics[1] != safeTopic) {
                continue;
            }
            require(!_hasSignature(logs[i], VOTE_CAST_EVENT_SIGNATURE), "AerodromeVeSafe: Governor VoteCast by safe");
            require(
                !_hasSignature(logs[i], VOTE_CAST_WITH_PARAMS_EVENT_SIGNATURE),
                "AerodromeVeSafe: Governor VoteCastWithParams by safe"
            );
        }
    }

    function _requireNoCall(address target, bytes4 selector, string memory reason) internal view {
        if (target == address(0)) return;

        PhEvm.TriggerCall[] memory calls = _matchingCalls(target, selector, 1);
        require(calls.length == 0, reason);
    }

    function _requireNoVeCustodyCalls() internal view {
        _requireNoCall(VE, IAerodromeVeSafeVotingEscrowLike.approve.selector, "AerodromeVeSafe: veAERO approve call");
        _requireNoCall(
            VE,
            IAerodromeVeSafeVotingEscrowLike.setApprovalForAll.selector,
            "AerodromeVeSafe: veAERO setApprovalForAll call"
        );
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.transferFrom.selector, "AerodromeVeSafe: veAERO transferFrom call"
        );
        _requireNoCall(VE, SAFE_TRANSFER_FROM_SELECTOR, "AerodromeVeSafe: veAERO safeTransferFrom call");
        _requireNoCall(VE, SAFE_TRANSFER_FROM_WITH_DATA_SELECTOR, "AerodromeVeSafe: veAERO safeTransferFrom data call");
        _requireNoCall(VE, IAerodromeVeSafeVotingEscrowLike.withdraw.selector, "AerodromeVeSafe: veAERO withdraw call");
        _requireNoCall(
            VE,
            IAerodromeVeSafeVotingEscrowLike.createManagedLockFor.selector,
            "AerodromeVeSafe: veAERO createManagedLockFor call"
        );
        _requireNoCall(VE, IAerodromeVeSafeVotingEscrowLike.merge.selector, "AerodromeVeSafe: veAERO merge call");
        _requireNoCall(VE, IAerodromeVeSafeVotingEscrowLike.split.selector, "AerodromeVeSafe: veAERO split call");
    }

    function _requireNoVeVotingPowerCalls() internal view {
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.depositFor.selector, "AerodromeVeSafe: veAERO depositFor call"
        );
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.createLock.selector, "AerodromeVeSafe: veAERO createLock call"
        );
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.createLockFor.selector, "AerodromeVeSafe: veAERO createLockFor call"
        );
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.increaseAmount.selector, "AerodromeVeSafe: veAERO increaseAmount call"
        );
        _requireNoCall(
            VE,
            IAerodromeVeSafeVotingEscrowLike.increaseUnlockTime.selector,
            "AerodromeVeSafe: veAERO increaseUnlockTime call"
        );
        _requireNoCall(VE, IAerodromeVeSafeVotingEscrowLike.delegate.selector, "AerodromeVeSafe: veAERO delegate call");
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.delegateBySig.selector, "AerodromeVeSafe: veAERO delegateBySig call"
        );
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.depositManaged.selector, "AerodromeVeSafe: veAERO depositManaged call"
        );
        _requireNoCall(
            VE,
            IAerodromeVeSafeVotingEscrowLike.withdrawManaged.selector,
            "AerodromeVeSafe: veAERO withdrawManaged call"
        );
        _requireNoCall(
            VE, IAerodromeVeSafeVotingEscrowLike.lockPermanent.selector, "AerodromeVeSafe: veAERO lockPermanent call"
        );
        _requireNoCall(
            VE,
            IAerodromeVeSafeVotingEscrowLike.unlockPermanent.selector,
            "AerodromeVeSafe: veAERO unlockPermanent call"
        );
    }

    function _requireNoVoterVotingPowerCalls() internal view {
        _requireNoCall(VOTER, IAerodromeVeSafeVoterLike.vote.selector, "AerodromeVeSafe: Voter vote call");
        _requireNoCall(VOTER, IAerodromeVeSafeVoterLike.reset.selector, "AerodromeVeSafe: Voter reset call");
        _requireNoCall(VOTER, IAerodromeVeSafeVoterLike.poke.selector, "AerodromeVeSafe: Voter poke call");
        _requireNoCall(
            VOTER, IAerodromeVeSafeVoterLike.depositManaged.selector, "AerodromeVeSafe: Voter depositManaged call"
        );
        _requireNoCall(
            VOTER, IAerodromeVeSafeVoterLike.withdrawManaged.selector, "AerodromeVeSafe: Voter withdrawManaged call"
        );
    }

    function _requireNoGovernorVoteCalls(address governor) internal view {
        _requireNoCall(
            governor, IAerodromeVeSafeGovernorLike.castVote.selector, "AerodromeVeSafe: Governor castVote call"
        );
        _requireNoCall(
            governor,
            IAerodromeVeSafeGovernorLike.castVoteWithReason.selector,
            "AerodromeVeSafe: Governor castVoteWithReason call"
        );
        _requireNoCall(
            governor,
            IAerodromeVeSafeGovernorLike.castVoteWithReasonAndParams.selector,
            "AerodromeVeSafe: Governor castVoteWithReasonAndParams call"
        );
        _requireNoCall(
            governor,
            IAerodromeVeSafeGovernorLike.castVoteBySig.selector,
            "AerodromeVeSafe: Governor castVoteBySig call"
        );
        _requireNoCall(
            governor,
            IAerodromeVeSafeGovernorLike.castVoteWithReasonAndParamsBySig.selector,
            "AerodromeVeSafe: Governor castVoteWithReasonAndParamsBySig call"
        );
    }

    function _hasSignature(PhEvm.Log memory log, bytes32 signature) internal pure returns (bool) {
        return log.topics.length != 0 && log.topics[0] == signature;
    }
}
