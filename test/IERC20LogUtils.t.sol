// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PhEvm} from "../src/PhEvm.sol";
import {IERC20LogUtils} from "../src/utils/IERC20LogUtils.sol";

contract IERC20LogUtilsHarness {
    function transferEventSignature() external pure returns (bytes32) {
        return IERC20LogUtils.TRANSFER_EVENT_SIGNATURE;
    }

    function approvalEventSignature() external pure returns (bytes32) {
        return IERC20LogUtils.APPROVAL_EVENT_SIGNATURE;
    }

    function transferQuery(address token) external pure returns (PhEvm.LogQuery memory) {
        return IERC20LogUtils.transferQuery(token);
    }

    function approvalQuery(address token) external pure returns (PhEvm.LogQuery memory) {
        return IERC20LogUtils.approvalQuery(token);
    }

    function isTransfer(PhEvm.Log memory log) external pure returns (bool) {
        return IERC20LogUtils.isTransfer(log);
    }

    function isApproval(PhEvm.Log memory log) external pure returns (bool) {
        return IERC20LogUtils.isApproval(log);
    }

    function decodeTransfer(PhEvm.Log memory log) external pure returns (PhEvm.Erc20TransferData memory) {
        return IERC20LogUtils.decodeTransfer(log);
    }

    function decodeApproval(PhEvm.Log memory log) external pure returns (IERC20LogUtils.ApprovalData memory) {
        return IERC20LogUtils.decodeApproval(log);
    }

    function decodeTransfers(PhEvm.Log[] memory logs) external pure returns (PhEvm.Erc20TransferData[] memory) {
        return IERC20LogUtils.decodeTransfers(logs);
    }

    function decodeApprovals(PhEvm.Log[] memory logs) external pure returns (IERC20LogUtils.ApprovalData[] memory) {
        return IERC20LogUtils.decodeApprovals(logs);
    }
}

contract IERC20LogUtilsTest is Test {
    IERC20LogUtilsHarness private harness;

    address private constant TOKEN = address(0x1000);
    address private constant FROM = address(0x2000);
    address private constant TO = address(0x3000);
    uint256 private constant VALUE = 123 ether;

    function setUp() public {
        harness = new IERC20LogUtilsHarness();
    }

    function testEventSignatures() public view {
        assertEq(harness.transferEventSignature(), keccak256("Transfer(address,address,uint256)"));
        assertEq(harness.approvalEventSignature(), keccak256("Approval(address,address,uint256)"));
    }

    function testQueries() public view {
        PhEvm.LogQuery memory transferQuery = harness.transferQuery(TOKEN);
        assertEq(transferQuery.emitter, TOKEN);
        assertEq(transferQuery.signature, keccak256("Transfer(address,address,uint256)"));

        PhEvm.LogQuery memory approvalQuery = harness.approvalQuery(TOKEN);
        assertEq(approvalQuery.emitter, TOKEN);
        assertEq(approvalQuery.signature, keccak256("Approval(address,address,uint256)"));
    }

    function testDecodeTransfer() public view {
        PhEvm.Log memory log = _erc20Log(keccak256("Transfer(address,address,uint256)"), FROM, TO, VALUE);

        assertTrue(harness.isTransfer(log));
        assertFalse(harness.isApproval(log));

        PhEvm.Erc20TransferData memory transfer = harness.decodeTransfer(log);
        assertEq(transfer.token_addr, TOKEN);
        assertEq(transfer.from, FROM);
        assertEq(transfer.to, TO);
        assertEq(transfer.value, VALUE);
    }

    function testDecodeApproval() public view {
        PhEvm.Log memory log = _erc20Log(keccak256("Approval(address,address,uint256)"), FROM, TO, VALUE);

        assertTrue(harness.isApproval(log));
        assertFalse(harness.isTransfer(log));

        IERC20LogUtils.ApprovalData memory approval = harness.decodeApproval(log);
        assertEq(approval.token_addr, TOKEN);
        assertEq(approval.owner, FROM);
        assertEq(approval.spender, TO);
        assertEq(approval.value, VALUE);
    }

    function testDecodeTransferArray() public view {
        PhEvm.Log[] memory logs = new PhEvm.Log[](2);
        logs[0] = _erc20Log(keccak256("Transfer(address,address,uint256)"), FROM, TO, 1);
        logs[1] = _erc20Log(keccak256("Transfer(address,address,uint256)"), TO, FROM, 2);

        PhEvm.Erc20TransferData[] memory transfers = harness.decodeTransfers(logs);
        assertEq(transfers.length, 2);
        assertEq(transfers[0].from, FROM);
        assertEq(transfers[0].to, TO);
        assertEq(transfers[0].value, 1);
        assertEq(transfers[1].from, TO);
        assertEq(transfers[1].to, FROM);
        assertEq(transfers[1].value, 2);
    }

    function testDecodeApprovalArray() public view {
        PhEvm.Log[] memory logs = new PhEvm.Log[](2);
        logs[0] = _erc20Log(keccak256("Approval(address,address,uint256)"), FROM, TO, 1);
        logs[1] = _erc20Log(keccak256("Approval(address,address,uint256)"), TO, FROM, 2);

        IERC20LogUtils.ApprovalData[] memory approvals = harness.decodeApprovals(logs);
        assertEq(approvals.length, 2);
        assertEq(approvals[0].owner, FROM);
        assertEq(approvals[0].spender, TO);
        assertEq(approvals[0].value, 1);
        assertEq(approvals[1].owner, TO);
        assertEq(approvals[1].spender, FROM);
        assertEq(approvals[1].value, 2);
    }

    function testInvalidTransferLogReverts() public {
        PhEvm.Log memory log = _erc20Log(keccak256("Approval(address,address,uint256)"), FROM, TO, VALUE);

        vm.expectRevert("IERC20LogUtils: invalid Transfer log");
        harness.decodeTransfer(log);
    }

    function testInvalidApprovalLogReverts() public {
        PhEvm.Log memory log = _erc20Log(keccak256("Transfer(address,address,uint256)"), FROM, TO, VALUE);

        vm.expectRevert("IERC20LogUtils: invalid Approval log");
        harness.decodeApproval(log);
    }

    function testMalformedLogIsNotRecognized() public view {
        PhEvm.Log memory log = _erc20Log(keccak256("Transfer(address,address,uint256)"), FROM, TO, VALUE);
        log.data = abi.encode(VALUE, VALUE);

        assertFalse(harness.isTransfer(log));
        assertFalse(harness.isApproval(log));
    }

    function _erc20Log(bytes32 signature, address topic1, address topic2, uint256 value)
        private
        pure
        returns (PhEvm.Log memory log)
    {
        log.emitter = TOKEN;
        log.topics = new bytes32[](3);
        log.topics[0] = signature;
        log.topics[1] = bytes32(uint256(uint160(topic1)));
        log.topics[2] = bytes32(uint256(uint160(topic2)));
        log.data = abi.encode(value);
    }
}
