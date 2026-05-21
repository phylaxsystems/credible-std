// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal veAERO VotingEscrow surface used by Safe guardian assertions.
interface IAerodromeVeSafeVotingEscrowLike {
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function depositFor(uint256 tokenId, uint256 value) external;
    function createLock(uint256 value, uint256 lockDuration) external returns (uint256 tokenId);
    function createLockFor(uint256 value, uint256 lockDuration, address to) external returns (uint256 tokenId);
    function createManagedLockFor(address to) external returns (uint256 mTokenId);
    function increaseAmount(uint256 tokenId, uint256 value) external;
    function increaseUnlockTime(uint256 tokenId, uint256 lockDuration) external;
    function depositManaged(uint256 tokenId, uint256 mTokenId) external;
    function withdrawManaged(uint256 tokenId) external;
    function withdraw(uint256 tokenId) external;
    function merge(uint256 from, uint256 to) external;
    function split(uint256 from, uint256 amount) external returns (uint256 tokenId1, uint256 tokenId2);
    function lockPermanent(uint256 tokenId) external;
    function unlockPermanent(uint256 tokenId) external;
    function delegate(uint256 delegator, uint256 delegatee) external;
    function delegateBySig(
        uint256 delegator,
        uint256 delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Minimal Aerodrome Voter surface that changes veNFT voting power or placement.
interface IAerodromeVeSafeVoterLike {
    function vote(uint256 tokenId, address[] calldata poolVote, uint256[] calldata weights) external;
    function reset(uint256 tokenId) external;
    function poke(uint256 tokenId) external;
    function depositManaged(uint256 tokenId, uint256 mTokenId) external;
    function withdrawManaged(uint256 tokenId) external;
}

/// @notice Minimal ProtocolGovernor/EpochGovernor token-id voting surface.
interface IAerodromeVeSafeGovernorLike {
    function castVote(uint256 proposalId, uint256 tokenId, uint8 support) external returns (uint256 balance);
    function castVoteWithReason(uint256 proposalId, uint256 tokenId, uint8 support, string calldata reason)
        external
        returns (uint256 balance);
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) external returns (uint256 balance);
    function castVoteBySig(uint256 proposalId, uint256 tokenId, uint8 support, uint8 v, bytes32 r, bytes32 s)
        external
        returns (uint256 balance);
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason,
        bytes calldata params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 balance);
}
