// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestMatchingCalls is Assertion {
    constructor() payable {}

    function _anyFilter() internal pure returns (PhEvm.CallFilter memory) {
        return PhEvm.CallFilter({
            callType: 0, minDepth: 0, maxDepth: type(uint32).max, topLevelOnly: false, successOnly: false
        });
    }

    function matchesAllWriteCalls() external view {
        PhEvm.TriggerCall[] memory calls =
            ph.matchingCalls(address(TARGET), Target.writeStorage.selector, _anyFilter(), 10);
        require(calls.length == 3, "expected 3 writeStorage calls (incl. nested)");

        for (uint256 i = 0; i < calls.length; i++) {
            require(calls[i].target == address(TARGET), "target mismatch");
            require(calls[i].selector == Target.writeStorage.selector, "selector mismatch");
        }
    }

    function staticCallTypeFilterMatchesOnlyStaticCalls() external view {
        PhEvm.CallFilter memory filter = _anyFilter();
        filter.callType = 2; // STATICCALL

        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(address(TARGET), Target.readStorage.selector, filter, 10);
        require(calls.length == 1, "expected exactly 1 staticcall to readStorage");
        require(calls[0].callType == 2, "callType != STATICCALL");
    }

    function callTypeFilterExcludesStaticCalls() external view {
        PhEvm.CallFilter memory filter = _anyFilter();
        filter.callType = 1; // CALL

        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(address(TARGET), Target.readStorage.selector, filter, 10);
        require(calls.length == 0, "CALL filter should not match staticcall");
    }

    function topLevelOnlyExcludesNestedCalls() external view {
        PhEvm.CallFilter memory filter = _anyFilter();
        filter.topLevelOnly = true;

        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(address(TARGET), Target.writeStorage.selector, filter, 10);
        // Only the top-level writeStorage(1) call is depth==1; the call from incrementStorage is nested.
        require(calls.length == 1, "expected 1 top-level writeStorage");
        require(calls[0].depth == 1, "depth != 1");
    }

    function successOnlyExcludesFailedCalls() external view {
        PhEvm.CallFilter memory filter = _anyFilter();
        filter.successOnly = true;

        PhEvm.TriggerCall[] memory calls =
            ph.matchingCalls(address(TARGET), Target.writeStorageAndRevert.selector, filter, 10);
        require(calls.length == 0, "successOnly should exclude the reverting call");

        filter.successOnly = false;
        calls = ph.matchingCalls(address(TARGET), Target.writeStorageAndRevert.selector, filter, 10);
        require(calls.length == 1, "expected 1 reverting call when successOnly=false");
        require(!calls[0].success, "expected success=false");
    }

    function limitTruncatesResultArray() external view {
        PhEvm.TriggerCall[] memory calls =
            ph.matchingCalls(address(TARGET), Target.writeStorage.selector, _anyFilter(), 1);
        require(calls.length == 1, "limit=1 should truncate to 1 result");
    }

    function triggers() external view override {
        registerCallTrigger(this.matchesAllWriteCalls.selector);
        registerCallTrigger(this.staticCallTypeFilterMatchesOnlyStaticCalls.selector);
        registerCallTrigger(this.callTypeFilterExcludesStaticCalls.selector);
        registerCallTrigger(this.topLevelOnlyExcludesNestedCalls.selector);
        registerCallTrigger(this.successOnlyExcludesFailedCalls.selector);
        registerCallTrigger(this.limitTruncatesResultArray.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
        TARGET.incrementStorage(); // nested writeStorage(2)
        TARGET.readStorage(); // staticcall
        try TARGET.writeStorageAndRevert(99) {
            revert("expected revert");
        } catch {}
    }
}
