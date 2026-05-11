// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestGetLogsForCall is Assertion {
    constructor() payable {}

    function _anyEmitter() internal pure returns (PhEvm.LogQuery memory) {
        return PhEvm.LogQuery({emitter: address(0), signature: bytes32(0)});
    }

    function _logQueryForTarget() internal pure returns (PhEvm.LogQuery memory) {
        return PhEvm.LogQuery({emitter: address(TARGET), signature: Target.Log.selector});
    }

    function logsAreScopedToTheirCall() external view {
        PhEvm.CallInputs[] memory writes = ph.getCallInputs(address(TARGET), Target.writeStorage.selector);
        require(writes.length == 2, "expected 2 writeStorage calls");

        PhEvm.Log[] memory firstLogs = ph.getLogsForCall(_logQueryForTarget(), writes[0].id);
        require(firstLogs.length == 1, "first call: expected 1 log");
        require(firstLogs[0].emitter == address(TARGET), "first log emitter mismatch");
        require(bytes32(firstLogs[0].data) == bytes32(uint256(11)), "first log data != 11");

        PhEvm.Log[] memory secondLogs = ph.getLogsForCall(_logQueryForTarget(), writes[1].id);
        require(secondLogs.length == 1, "second call: expected 1 log");
        require(bytes32(secondLogs[0].data) == bytes32(uint256(22)), "second log data != 22");
    }

    function emptyQueryReturnsAllLogsInCallFrame() external view {
        PhEvm.CallInputs[] memory writes = ph.getCallInputs(address(TARGET), Target.writeStorage.selector);
        require(writes.length == 2, "expected 2 writeStorage calls");

        PhEvm.Log[] memory logs = ph.getLogsForCall(_anyEmitter(), writes[0].id);
        require(logs.length == 1, "expected 1 log in first call frame");
    }

    function nonMatchingSignatureReturnsEmpty() external view {
        PhEvm.CallInputs[] memory writes = ph.getCallInputs(address(TARGET), Target.writeStorage.selector);
        require(writes.length == 2, "expected 2 writeStorage calls");

        PhEvm.LogQuery memory query =
            PhEvm.LogQuery({emitter: address(TARGET), signature: keccak256("Nonexistent(uint256)")});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, writes[0].id);
        require(logs.length == 0, "non-matching signature should return empty");
    }

    function callWithoutLogsReturnsEmpty() external view {
        PhEvm.CallInputs[] memory reads = ph.getStaticCallInputs(address(TARGET), Target.readStorage.selector);
        require(reads.length == 1, "expected 1 readStorage staticcall");

        PhEvm.Log[] memory logs = ph.getLogsForCall(_anyEmitter(), reads[0].id);
        require(logs.length == 0, "readStorage emits no logs");
    }

    function triggers() external view override {
        registerCallTrigger(this.logsAreScopedToTheirCall.selector);
        registerCallTrigger(this.emptyQueryReturnsAllLogsInCallFrame.selector);
        registerCallTrigger(this.nonMatchingSignatureReturnsEmpty.selector);
        registerCallTrigger(this.callWithoutLogsReturnsEmpty.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(11);
        TARGET.writeStorage(22);
        TARGET.readStorage();
    }
}
