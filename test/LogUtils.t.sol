// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LogUtils} from "../src/utils/LogUtils.sol";
import {PhEvm} from "../src/PhEvm.sol";

contract LogUtilsTest is Test {
    using LogUtils for PhEvm.Log;
    using LogUtils for PhEvm.Log[];

    bytes32 constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    bytes32 constant APPROVAL_SIG = keccak256("Approval(address,address,uint256)");

    address constant TOKEN_A = address(0xA11CE);
    address constant TOKEN_B = address(0xB0B);
    address constant USER_1 = address(0x1111);
    address constant USER_2 = address(0x2222);

    function _makeLog(address emitter, bytes32[] memory topics, bytes memory data)
        internal
        pure
        returns (PhEvm.Log memory log)
    {
        log.emitter = emitter;
        log.topics = topics;
        log.data = data;
    }

    function _transferLog(address emitter, address from, address to, uint256 value)
        internal
        pure
        returns (PhEvm.Log memory)
    {
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = TRANSFER_SIG;
        topics[1] = LogUtils.topic(from);
        topics[2] = LogUtils.topic(to);
        return _makeLog(emitter, topics, abi.encode(value));
    }

    // ---- sig ----

    function test_sig_returnsTopic0() public pure {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = TRANSFER_SIG;
        PhEvm.Log memory log = _makeLog(TOKEN_A, topics, "");
        assertEq(LogUtils.sig(log), TRANSFER_SIG);
    }

    function test_sig_anonymousReturnsZero() public pure {
        bytes32[] memory topics = new bytes32[](0);
        PhEvm.Log memory log = _makeLog(TOKEN_A, topics, hex"deadbeef");
        assertEq(LogUtils.sig(log), bytes32(0));
    }

    // ---- isSig ----

    function test_isSig_match() public pure {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 100);
        assertTrue(LogUtils.isSig(log, TRANSFER_SIG));
        assertFalse(LogUtils.isSig(log, APPROVAL_SIG));
    }

    function test_isSig_anonymousNeverMatchesNonZero() public pure {
        bytes32[] memory topics = new bytes32[](0);
        PhEvm.Log memory log = _makeLog(TOKEN_A, topics, "");
        assertFalse(LogUtils.isSig(log, TRANSFER_SIG));
        assertTrue(LogUtils.isSig(log, bytes32(0)));
    }

    // ---- isFrom ----

    function test_isFrom() public pure {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 0);
        assertTrue(LogUtils.isFrom(log, TOKEN_A));
        assertFalse(LogUtils.isFrom(log, TOKEN_B));
    }

    // ---- isEvent ----

    function test_isEvent_bothMatch() public pure {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 1);
        assertTrue(LogUtils.isEvent(log, TOKEN_A, TRANSFER_SIG));
        assertFalse(LogUtils.isEvent(log, TOKEN_B, TRANSFER_SIG));
        assertFalse(LogUtils.isEvent(log, TOKEN_A, APPROVAL_SIG));
    }

    // ---- indexedTopic ----

    function test_indexedTopic_skipsTopic0() public pure {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 0);
        assertEq(LogUtils.indexedTopic(log, 0), LogUtils.topic(USER_1));
        assertEq(LogUtils.indexedTopic(log, 1), LogUtils.topic(USER_2));
    }

    function test_indexedTopic_outOfBoundsReverts() public {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 0);
        // topics.length == 3, so indexedIdx 2 -> log.topics[3] reverts
        vm.expectRevert();
        this.callIndexedTopic(log, 2);
    }

    function test_indexedTopic_anonymousAlwaysReverts() public {
        bytes32[] memory topics = new bytes32[](0);
        PhEvm.Log memory log = _makeLog(TOKEN_A, topics, "");
        vm.expectRevert();
        this.callIndexedTopic(log, 0);
    }

    function callIndexedTopic(PhEvm.Log memory log, uint256 idx) external pure returns (bytes32) {
        return LogUtils.indexedTopic(log, idx);
    }

    // ---- indexedAddress / indexedUint / indexedBool ----

    function test_indexedAddress_decodesLowerBytes() public pure {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 0);
        assertEq(LogUtils.indexedAddress(log, 0), USER_1);
        assertEq(LogUtils.indexedAddress(log, 1), USER_2);
    }

    function test_indexedUint() public pure {
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = bytes32(uint256(0xdead));
        topics[1] = bytes32(uint256(123456));
        PhEvm.Log memory log = _makeLog(TOKEN_A, topics, "");
        assertEq(LogUtils.indexedUint(log, 0), 123456);
    }

    function test_indexedBool_trueAndFalse() public pure {
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = bytes32(uint256(0xdead));
        topics[1] = bytes32(uint256(0));
        topics[2] = bytes32(uint256(1));
        PhEvm.Log memory log = _makeLog(TOKEN_A, topics, "");
        assertFalse(LogUtils.indexedBool(log, 0));
        assertTrue(LogUtils.indexedBool(log, 1));
    }

    // ---- topic encoding ----

    function test_topic_address_leftPads() public pure {
        bytes32 t = LogUtils.topic(USER_1);
        assertEq(t, bytes32(uint256(uint160(USER_1))));
        assertEq(uint256(t) >> 160, 0);
    }

    function test_topic_uint256() public pure {
        assertEq(LogUtils.topic(uint256(0)), bytes32(0));
        assertEq(LogUtils.topic(type(uint256).max), bytes32(type(uint256).max));
        assertEq(LogUtils.topic(uint256(42)), bytes32(uint256(42)));
    }

    // ---- first ----

    function test_first_emptyArray() public pure {
        PhEvm.Log[] memory logs = new PhEvm.Log[](0);
        (bool found, PhEvm.Log memory log) = LogUtils.first(logs, TOKEN_A, TRANSFER_SIG);
        assertFalse(found);
        assertEq(log.emitter, address(0));
        assertEq(log.topics.length, 0);
    }

    function test_first_returnsFirstMatch() public pure {
        PhEvm.Log[] memory logs = new PhEvm.Log[](3);
        logs[0] = _transferLog(TOKEN_B, USER_1, USER_2, 1); // wrong emitter
        logs[1] = _transferLog(TOKEN_A, USER_1, USER_2, 7); // first match
        logs[2] = _transferLog(TOKEN_A, USER_2, USER_1, 9); // second match (skipped)
        (bool found, PhEvm.Log memory log) = LogUtils.first(logs, TOKEN_A, TRANSFER_SIG);
        assertTrue(found);
        assertEq(log.emitter, TOKEN_A);
        assertEq(abi.decode(log.data, (uint256)), 7);
    }

    function test_first_noneMatch() public pure {
        PhEvm.Log[] memory logs = new PhEvm.Log[](2);
        logs[0] = _transferLog(TOKEN_B, USER_1, USER_2, 1);
        logs[1] = _transferLog(TOKEN_B, USER_2, USER_1, 2);
        (bool found,) = LogUtils.first(logs, TOKEN_A, TRANSFER_SIG);
        assertFalse(found);
    }

    // ---- count ----

    function test_count_empty() public pure {
        PhEvm.Log[] memory logs = new PhEvm.Log[](0);
        assertEq(LogUtils.count(logs, TOKEN_A, TRANSFER_SIG), 0);
    }

    function test_count_mixed() public pure {
        PhEvm.Log[] memory logs = new PhEvm.Log[](5);
        logs[0] = _transferLog(TOKEN_A, USER_1, USER_2, 1);
        logs[1] = _transferLog(TOKEN_B, USER_1, USER_2, 2);
        logs[2] = _transferLog(TOKEN_A, USER_2, USER_1, 3);
        // approval on TOKEN_A (different sig)
        bytes32[] memory approvalTopics = new bytes32[](3);
        approvalTopics[0] = APPROVAL_SIG;
        approvalTopics[1] = LogUtils.topic(USER_1);
        approvalTopics[2] = LogUtils.topic(USER_2);
        logs[3] = _makeLog(TOKEN_A, approvalTopics, abi.encode(uint256(0)));
        logs[4] = _transferLog(TOKEN_A, USER_1, USER_2, 4);
        assertEq(LogUtils.count(logs, TOKEN_A, TRANSFER_SIG), 3);
        assertEq(LogUtils.count(logs, TOKEN_A, APPROVAL_SIG), 1);
        assertEq(LogUtils.count(logs, TOKEN_B, TRANSFER_SIG), 1);
    }

    // ---- using-for syntax ----

    function test_usingFor() public pure {
        PhEvm.Log memory log = _transferLog(TOKEN_A, USER_1, USER_2, 5);
        assertTrue(log.isEvent(TOKEN_A, TRANSFER_SIG));
        assertEq(log.indexedAddress(0), USER_1);

        PhEvm.Log[] memory logs = new PhEvm.Log[](1);
        logs[0] = log;
        assertEq(logs.count(TOKEN_A, TRANSFER_SIG), 1);
    }
}
