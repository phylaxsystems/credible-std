// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestCallOutputAt is Assertion {
    constructor() payable {}

    function callOutputAtReturnsEncodedReturnData() external view {
        PhEvm.CallInputs[] memory readCalls = ph.getStaticCallInputs(address(TARGET), Target.readStorage.selector);
        require(readCalls.length == 1, "expected one readStorage call");

        bytes memory output = ph.callOutputAt(readCalls[0].id);
        require(abi.decode(output, (uint256)) == 7, "unexpected readStorage output");
    }

    function callOutputAtReturnsEmptyBytesForVoidCall() external view {
        bytes memory output = ph.callOutputAt(_successfulNestedWriteId());
        require(output.length == 0, "void call should return empty bytes");
    }

    function callOutputAtReturnsRevertData() external view {
        bytes memory output = ph.callOutputAt(_revertedWriteStorageAndRevertId());
        require(output.length >= 4, "reverting call should return revert bytes");
    }

    function callOutputAtRejectsRevertedSubtreeCallId() external view {
        uint256 revertedCallId = _revertedSubtreeChildCallId();
        bytes memory calldata_ = abi.encodeWithSelector(PhEvm.callOutputAt.selector, revertedCallId);
        (bool success,) = address(ph).staticcall(calldata_);
        require(!success, "reverted subtree call should revert");
    }

    function _successfulNestedWriteId() internal view returns (uint256 successfulNestedWriteId) {
        PhEvm.CallInputs[] memory writeCalls = ph.getCallInputs(address(TARGET), Target.writeStorage.selector);

        bool found;
        for (uint256 i = 0; i < writeCalls.length; i++) {
            uint256 param = abi.decode(writeCalls[i].input, (uint256));
            if (param == 7) {
                successfulNestedWriteId = writeCalls[i].id;
                found = true;
                break;
            }
        }

        require(found, "expected nested writeStorage call");
    }

    function _revertedWriteStorageAndRevertId() internal view returns (uint256) {
        return _successfulNestedWriteId() + 1;
    }

    function _revertedSubtreeChildCallId() internal view returns (uint256) {
        return _revertedWriteStorageAndRevertId() + 2;
    }

    function triggers() external view override {
        registerCallTrigger(this.callOutputAtReturnsEncodedReturnData.selector);
        registerCallTrigger(this.callOutputAtReturnsEmptyBytesForVoidCall.selector);
        registerCallTrigger(this.callOutputAtReturnsRevertData.selector);
        registerCallTrigger(this.callOutputAtRejectsRevertedSubtreeCallId.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(5);

        CallFrameTrigger callFrameTrigger = new CallFrameTrigger();
        callFrameTrigger.trigger();

        RevertingSubtreeTrigger revertingSubtreeTrigger = new RevertingSubtreeTrigger();
        try revertingSubtreeTrigger.trigger() {
            revert("expected reverting subtree to revert");
        } catch {}

        uint256 value = TARGET.readStorage();
        require(value == 7, "readStorage call failed");
    }
}

contract CallFrameTrigger {
    function trigger() external {
        TARGET.writeStorage(7);

        try TARGET.writeStorageAndRevert(11) {
            revert("expected writeStorageAndRevert to revert");
        } catch {}
    }
}

contract RevertingSubtreeTrigger {
    function trigger() external {
        TARGET.writeStorage(9);
        revert("reverted subtree");
    }
}
