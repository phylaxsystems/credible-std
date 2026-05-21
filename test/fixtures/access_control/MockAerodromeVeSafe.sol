// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockSafe {
    event Executed(address indexed target, bytes data);

    function execute(address target, bytes calldata data) external returns (bytes memory result) {
        (bool ok, bytes memory returndata) = target.call(data);
        require(ok, "MockSafe: execution failed");

        emit Executed(target, data);
        return returndata;
    }
}

contract MockNoopTarget {
    event Ping(address indexed sender);

    function ping() external {
        emit Ping(msg.sender);
    }
}

contract MockAerodromeVeSafeVotingEscrow {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event DelegateChanged(address indexed delegator, uint256 indexed fromDelegate, uint256 indexed toDelegate);
    event Checkpoint(address indexed sender);

    function approve(address approved, uint256 tokenId) external {
        emit Approval(msg.sender, approved, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        emit Transfer(from, to, tokenId);
    }

    function createManagedLockFor(address) external pure returns (uint256 mTokenId) {
        return 100;
    }

    function depositManaged(uint256, uint256) external {}

    function withdrawManaged(uint256) external {}

    function withdraw(uint256 tokenId) external {
        emit Transfer(msg.sender, address(0), tokenId);
    }

    function merge(uint256, uint256) external {}

    function split(uint256, uint256) external pure returns (uint256 tokenId1, uint256 tokenId2) {
        return (101, 102);
    }

    function lockPermanent(uint256) external {}

    function unlockPermanent(uint256) external {}

    function delegate(uint256 fromDelegate, uint256 toDelegate) external {
        emit DelegateChanged(msg.sender, fromDelegate, toDelegate);
    }

    function delegateBySig(uint256 fromDelegate, uint256 toDelegate, uint256, uint256, uint8, bytes32, bytes32)
        external
    {
        emit DelegateChanged(msg.sender, fromDelegate, toDelegate);
    }

    function checkpoint() external {
        emit Checkpoint(msg.sender);
    }
}

contract MockAerodromeVeSafeVoter {
    event Voted(address indexed voter, uint256 indexed tokenId);
    event Reset(address indexed voter, uint256 indexed tokenId);
    event Poked(address indexed voter, uint256 indexed tokenId);
    event ManagedDeposit(address indexed voter, uint256 indexed tokenId, uint256 indexed mTokenId);
    event ManagedWithdraw(address indexed voter, uint256 indexed tokenId);

    function vote(uint256 tokenId, address[] calldata, uint256[] calldata) external {
        emit Voted(msg.sender, tokenId);
    }

    function reset(uint256 tokenId) external {
        emit Reset(msg.sender, tokenId);
    }

    function poke(uint256 tokenId) external {
        emit Poked(msg.sender, tokenId);
    }

    function depositManaged(uint256 tokenId, uint256 mTokenId) external {
        emit ManagedDeposit(msg.sender, tokenId, mTokenId);
    }

    function withdrawManaged(uint256 tokenId) external {
        emit ManagedWithdraw(msg.sender, tokenId);
    }
}

contract MockAerodromeVeSafeGovernor {
    event VoteCast(
        address indexed voter, uint256 indexed tokenId, uint256 proposalId, uint8 support, uint256 weight, string reason
    );
    event VoteCastWithParams(
        address indexed voter,
        uint256 indexed tokenId,
        uint256 proposalId,
        uint8 support,
        uint256 weight,
        string reason,
        bytes params
    );

    function castVote(uint256 proposalId, uint256 tokenId, uint8 support) external returns (uint256 balance) {
        emit VoteCast(msg.sender, tokenId, proposalId, support, 1, "");
        return 1;
    }

    function castVoteWithReason(uint256 proposalId, uint256 tokenId, uint8 support, string calldata reason)
        external
        returns (uint256 balance)
    {
        emit VoteCast(msg.sender, tokenId, proposalId, support, 1, reason);
        return 1;
    }

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) external returns (uint256 balance) {
        emit VoteCastWithParams(msg.sender, tokenId, proposalId, support, 1, reason, params);
        return 1;
    }

    function castVoteBySig(uint256 proposalId, uint256 tokenId, uint8 support, uint8, bytes32, bytes32)
        external
        returns (uint256 balance)
    {
        emit VoteCast(address(0xBEEF), tokenId, proposalId, support, 1, "");
        return 1;
    }

    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint256 tokenId,
        uint8 support,
        string calldata reason,
        bytes calldata params,
        uint8,
        bytes32,
        bytes32
    ) external returns (uint256 balance) {
        emit VoteCastWithParams(address(0xBEEF), tokenId, proposalId, support, 1, reason, params);
        return 1;
    }
}
