// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestCallOutputAt is Assertion {
    constructor() payable {}

    function callOutputAtReturnsEncodedReturnData() external view {
        PhEvm.CallInputs[] memory readCalls =
            ph.getStaticCallInputs(address(TARGET), Target.readStorage.selector);
        require(readCalls.length == 1, "expected one readStorage call");

        bytes memory output = ph.callOutputAt(readCalls[0].id);
        require(abi.decode(output, (uint256)) == 7, "unexpected readStorage output");
    }

    function callOutputAtReturnsEmptyBytesForVoidCall() external view {
        bytes memory output = ph.callOutputAt(_successfulNestedWriteId());
        require(output.length == 0, "void call should return empty bytes");
    }

    function callOutputAtReturnsRevertData() external view {
        PhEvm.CallInputs[] memory revertCalls =
            ph.getCallInputs(address(TARGET), Target.revertWithMessage.selector);
        require(revertCalls.length == 1, "expected one revertWithMessage call");

        bytes memory output = ph.callOutputAt(revertCalls[0].id);
        require(output.length >= 4, "reverting call should return revert bytes");
        require(_selector(output) == bytes4(keccak256("Error(string)")), "unexpected revert selector");
    }

    function callOutputAtRejectsRevertedSubtreeCallId() external view {
        uint256 revertedCallId = _successfulNestedWriteId() + 1;
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

    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            return bytes4(0);
        }

        assembly {
            selector := mload(add(data, 32))
        }
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

        uint256 value = TARGET.readStorage();
        require(value == 7, "readStorage call failed");

        (bool success,) = address(TARGET).call(abi.encodeCall(Target.revertWithMessage, ()));
        require(!success, "expected revertWithMessage to revert");
    }
}

contract CallFrameTrigger {
    function trigger() external {
        TARGET.writeStorage(7);

        try TARGET.writeStorageAndRevert(9) {
            revert("expected writeStorageAndRevert to revert");
        } catch {}
    }
}
