// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "./LidoMocks.sol";

/// @notice EasyTrack-style optimistic governance stand-in. `objectToMotion` is balance-weighted: it
///         records the caller's live governance-token balance as the objection weight — the exact
///         same-block read that the real EasyTrack snapshot makes, and the surface a flash loan
///         attacks. `createMotion` is included as a second protected entrypoint.
contract MockEasyTrack {
    struct Motion {
        uint256 id;
        address evmScriptFactory;
        address creator;
        uint256 duration;
        uint256 startDate;
        uint256 snapshotBlock;
        uint256 objectionsThreshold;
        uint256 objectionsAmount;
        bytes32 evmScriptHash;
    }

    MockERC20 public immutable governanceToken;

    /// @notice motionId => objector => weight credited at objection time.
    mapping(uint256 => mapping(address => uint256)) public objectionWeight;
    mapping(uint256 => uint256) public motionSnapshotBlock;
    uint256 public lastMotionId;

    constructor(MockERC20 governanceToken_) {
        governanceToken = governanceToken_;
    }

    function getMotion(uint256 motionId) external view returns (Motion memory motion) {
        motion.id = motionId;
        uint256 configured = motionSnapshotBlock[motionId];
        motion.snapshotBlock = configured == 0 ? block.number : configured;
    }

    function setMotionSnapshotBlock(uint256 motionId, uint256 snapshotBlock) external {
        motionSnapshotBlock[motionId] = snapshotBlock;
    }

    /// @dev Mirrors the vulnerable read: objection weight = live balance of the caller.
    function objectToMotion(uint256 motionId) external {
        objectionWeight[motionId][msg.sender] = governanceToken.balanceOf(msg.sender);
    }

    function createMotion(address factory, bytes calldata data) external returns (uint256 motionId) {
        factory;
        data;
        motionId = ++lastMotionId;
    }
}

/// @notice Flash-loan attacker: in a single transaction it borrows the governance token from a
///         lender, exercises a balance-weighted governance action with the borrowed power, then
///         repays. The lender must have approved this contract for `amount` beforehand.
contract MockFlashGovAttacker {
    /// @notice Borrow → object → repay, all in one transaction (one armed `cl.assertion` call).
    function flashObject(MockEasyTrack gov, MockERC20 token, address lender, uint256 motionId, uint256 amount)
        external
    {
        token.transferFrom(lender, address(this), amount); // borrow
        gov.objectToMotion(motionId); // exercise flash-loaned voting power
        token.transfer(lender, amount); // repay
    }
}

/// @notice Honest participant: holds its governance token across transactions and simply objects.
///         Used to prove the assertion does not flag power that was durably held at transaction start.
contract MockHonestObjector {
    function object(MockEasyTrack gov, uint256 motionId) external {
        gov.objectToMotion(motionId);
    }
}
