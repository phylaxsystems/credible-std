// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../PhEvm.sol";

/// @title IERC20LogUtils
/// @author Phylax Systems
/// @notice Helpers for querying and decoding standard ERC20 logs returned by PhEvm.
library IERC20LogUtils {
    /// @notice Standard ERC20 Transfer event signature.
    bytes32 internal constant TRANSFER_EVENT_SIGNATURE = keccak256("Transfer(address,address,uint256)");

    /// @notice Standard ERC20 Approval event signature.
    bytes32 internal constant APPROVAL_EVENT_SIGNATURE = keccak256("Approval(address,address,uint256)");

    /// @notice Decoded ERC20 Approval event data.
    struct ApprovalData {
        /// @notice The token contract that emitted the Approval event.
        address token_addr;
        /// @notice The token owner indexed in topic1.
        address owner;
        /// @notice The approved spender indexed in topic2.
        address spender;
        /// @notice The approved amount decoded from log data.
        uint256 value;
    }

    /// @notice Builds a PhEvm query for ERC20 Transfer logs emitted by `token`.
    /// @dev Pass address(0) to match Transfer logs from any emitter.
    function transferQuery(address token) internal pure returns (PhEvm.LogQuery memory query) {
        query = PhEvm.LogQuery({emitter: token, signature: TRANSFER_EVENT_SIGNATURE});
    }

    /// @notice Builds a PhEvm query for ERC20 Approval logs emitted by `token`.
    /// @dev Pass address(0) to match Approval logs from any emitter.
    function approvalQuery(address token) internal pure returns (PhEvm.LogQuery memory query) {
        query = PhEvm.LogQuery({emitter: token, signature: APPROVAL_EVENT_SIGNATURE});
    }

    /// @notice Returns true when `log` has the canonical ERC20 Transfer event shape.
    function isTransfer(PhEvm.Log memory log) internal pure returns (bool) {
        return log.topics.length == 3 && log.topics[0] == TRANSFER_EVENT_SIGNATURE && log.data.length == 32;
    }

    /// @notice Returns true when `log` has the canonical ERC20 Approval event shape.
    function isApproval(PhEvm.Log memory log) internal pure returns (bool) {
        return log.topics.length == 3 && log.topics[0] == APPROVAL_EVENT_SIGNATURE && log.data.length == 32;
    }

    /// @notice Decodes a canonical ERC20 Transfer log.
    function decodeTransfer(PhEvm.Log memory log) internal pure returns (PhEvm.Erc20TransferData memory transfer) {
        require(isTransfer(log), "IERC20LogUtils: invalid Transfer log");

        transfer = PhEvm.Erc20TransferData({
            token_addr: log.emitter,
            from: _topicAddress(log.topics[1]),
            to: _topicAddress(log.topics[2]),
            value: abi.decode(log.data, (uint256))
        });
    }

    /// @notice Decodes a canonical ERC20 Approval log.
    function decodeApproval(PhEvm.Log memory log) internal pure returns (ApprovalData memory approval) {
        require(isApproval(log), "IERC20LogUtils: invalid Approval log");

        approval = ApprovalData({
            token_addr: log.emitter,
            owner: _topicAddress(log.topics[1]),
            spender: _topicAddress(log.topics[2]),
            value: abi.decode(log.data, (uint256))
        });
    }

    /// @notice Decodes all logs as ERC20 Transfer events.
    /// @dev Reverts if any log is not a canonical Transfer event.
    function decodeTransfers(PhEvm.Log[] memory logs)
        internal
        pure
        returns (PhEvm.Erc20TransferData[] memory transfers)
    {
        transfers = new PhEvm.Erc20TransferData[](logs.length);

        for (uint256 i; i < logs.length; ++i) {
            transfers[i] = decodeTransfer(logs[i]);
        }
    }

    /// @notice Decodes all logs as ERC20 Approval events.
    /// @dev Reverts if any log is not a canonical Approval event.
    function decodeApprovals(PhEvm.Log[] memory logs) internal pure returns (ApprovalData[] memory approvals) {
        approvals = new ApprovalData[](logs.length);

        for (uint256 i; i < logs.length; ++i) {
            approvals[i] = decodeApproval(logs[i]);
        }
    }

    function _topicAddress(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
