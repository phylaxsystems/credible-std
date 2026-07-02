// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../src/CredibleTest.sol";
import {Assertion} from "../../src/Assertion.sol";
import {PhEvm} from "../../src/PhEvm.sol";
import {AssertionSpec} from "../../src/SpecRecorder.sol";

/// @notice Armed end-to-end battery for the `ph.matchingCalls` precompile.
/// @dev Every test here executes `ph.matchingCalls` through a real `cl.assertion` arming — never a
///      harness fed with hand-built bytes — so a pcl/executor build without the precompile fails
///      loudly with `Precompile selector not found: 0x0dc1cc5d` instead of staying silently green.
///      This is the regression test for the gap where the cheatcode shipped in the interface, docs,
///      and protection suites for months while no executor implemented it.
contract MatchingCallsTarget {
    uint256 public value;

    /// @dev Fans out two nested self-calls so the trace has same-selector calls at depth > 1,
    ///      and a caught reverted call whose subtree must be invisible to the precompile.
    function driver() external {
        try this.pokeReverting() {
            revert("expected pokeReverting to revert");
        } catch {}

        this.outer(7);
    }

    function outer(uint256 seed) external {
        this.inner(seed + 1);
        this.inner(seed + 2);
    }

    function inner(uint256 v) external {
        value = v;
    }

    function pokeReverting() external {
        value = type(uint256).max;
        revert("poke always reverts");
    }
}

contract MatchingCallsBatteryAssertion is Assertion {
    uint256 internal constant NO_PARENT = type(uint256).max;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerCallTrigger(this.assertTopLevelCallShape.selector);
        registerCallTrigger(this.assertNestedDepthAndParent.selector);
        registerCallTrigger(this.assertFiltersAndLimit.selector);
        registerCallTrigger(this.assertRevertedSubtreeInvisible.selector);
        registerCallTrigger(this.assertHelperMatchingCalls.selector);
    }

    function _anyFilter() internal pure returns (PhEvm.CallFilter memory filter) {
        filter = PhEvm.CallFilter({
            callType: 0,
            minDepth: 0,
            maxDepth: type(uint32).max,
            topLevelOnly: false,
            successOnly: true
        });
    }

    /// @notice The top-level `driver()` call: depth 1, no parent, CALL type, decodable metadata.
    function assertTopLevelCallShape() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.TriggerCall[] memory calls =
            ph.matchingCalls(adopter, MatchingCallsTarget.driver.selector, _anyFilter(), 32);

        require(calls.length == 1, "driver: expected exactly one call");
        require(calls[0].target == adopter, "driver: target mismatch");
        require(calls[0].selector == MatchingCallsTarget.driver.selector, "driver: selector mismatch");
        require(calls[0].depth == 1, "driver: depth != 1");
        require(calls[0].parentCallId == NO_PARENT, "driver: top-level call must have no parent");
        require(calls[0].callType == 1, "driver: callType != CALL");
        require(calls[0].success, "driver: success != true");
        require(calls[0].input.length == 0, "driver: input must be empty (no args)");
    }

    /// @notice Nested self-calls report increasing depth and chain to their enclosing call ids.
    function assertNestedDepthAndParent() external view {
        address adopter = ph.getAssertionAdopter();

        PhEvm.TriggerCall[] memory driverCalls =
            ph.matchingCalls(adopter, MatchingCallsTarget.driver.selector, _anyFilter(), 32);
        PhEvm.TriggerCall[] memory outerCalls =
            ph.matchingCalls(adopter, MatchingCallsTarget.outer.selector, _anyFilter(), 32);
        PhEvm.TriggerCall[] memory innerCalls =
            ph.matchingCalls(adopter, MatchingCallsTarget.inner.selector, _anyFilter(), 32);

        require(driverCalls.length == 1 && outerCalls.length == 1, "expected one driver and one outer call");
        require(innerCalls.length == 2, "expected two inner calls");

        require(outerCalls[0].depth == 2, "outer: depth != 2");
        require(outerCalls[0].parentCallId == driverCalls[0].callId, "outer: parent != driver");
        require(abi.decode(outerCalls[0].input, (uint256)) == 7, "outer: input != 7");

        // Execution order and selector-stripped ABI tails: inner(8) then inner(9).
        require(innerCalls[0].depth == 3 && innerCalls[1].depth == 3, "inner: depth != 3");
        require(innerCalls[0].parentCallId == outerCalls[0].callId, "inner[0]: parent != outer");
        require(innerCalls[1].parentCallId == outerCalls[0].callId, "inner[1]: parent != outer");
        require(abi.decode(innerCalls[0].input, (uint256)) == 8, "inner[0]: input != 8");
        require(abi.decode(innerCalls[1].input, (uint256)) == 9, "inner[1]: input != 9");
    }

    /// @notice Depth filters, topLevelOnly, and limit behave as declared.
    function assertFiltersAndLimit() external view {
        address adopter = ph.getAssertionAdopter();

        PhEvm.CallFilter memory filter = _anyFilter();
        filter.topLevelOnly = true;
        require(
            ph.matchingCalls(adopter, MatchingCallsTarget.inner.selector, filter, 32).length == 0,
            "topLevelOnly must exclude nested inner calls"
        );
        require(
            ph.matchingCalls(adopter, MatchingCallsTarget.driver.selector, filter, 32).length == 1,
            "topLevelOnly must keep the top-level driver call"
        );

        filter = _anyFilter();
        filter.minDepth = 3;
        require(
            ph.matchingCalls(adopter, MatchingCallsTarget.inner.selector, filter, 32).length == 2,
            "minDepth 3 must keep both inner calls"
        );
        require(
            ph.matchingCalls(adopter, MatchingCallsTarget.outer.selector, filter, 32).length == 0,
            "minDepth 3 must exclude the depth-2 outer call"
        );

        PhEvm.TriggerCall[] memory limited =
            ph.matchingCalls(adopter, MatchingCallsTarget.inner.selector, _anyFilter(), 1);
        require(limited.length == 1, "limit 1 must cap results");
        require(abi.decode(limited[0].input, (uint256)) == 8, "limit must keep execution order");
    }

    /// @notice A reverted-and-caught call's subtree is truncated at recording time and never
    ///         observable — even with `successOnly` disabled.
    function assertRevertedSubtreeInvisible() external view {
        address adopter = ph.getAssertionAdopter();
        PhEvm.CallFilter memory filter = _anyFilter();
        filter.successOnly = false;

        require(
            ph.matchingCalls(adopter, MatchingCallsTarget.pokeReverting.selector, filter, 32).length == 0,
            "reverted pokeReverting must not be recorded"
        );
    }

    /// @notice The `Assertion._matchingCalls` convenience wrapper drives the same precompile.
    function assertHelperMatchingCalls() external view {
        PhEvm.TriggerCall[] memory calls =
            _matchingCalls(ph.getAssertionAdopter(), MatchingCallsTarget.inner.selector, 32);
        require(calls.length == 2, "_matchingCalls: expected both inner calls");
    }
}

contract MatchingCallsPrecompileTest is Test, CredibleTest {
    MatchingCallsTarget internal target;

    function setUp() public {
        target = new MatchingCallsTarget();
    }

    function _arm(bytes4 fnSelector) internal {
        cl.assertion(address(target), type(MatchingCallsBatteryAssertion).creationCode, fnSelector);
    }

    function testTopLevelCallShape() public {
        _arm(MatchingCallsBatteryAssertion.assertTopLevelCallShape.selector);
        target.driver();
    }

    function testNestedDepthAndParent() public {
        _arm(MatchingCallsBatteryAssertion.assertNestedDepthAndParent.selector);
        target.driver();
    }

    function testFiltersAndLimit() public {
        _arm(MatchingCallsBatteryAssertion.assertFiltersAndLimit.selector);
        target.driver();
    }

    function testRevertedSubtreeInvisible() public {
        _arm(MatchingCallsBatteryAssertion.assertRevertedSubtreeInvisible.selector);
        target.driver();
    }

    function testHelperMatchingCalls() public {
        _arm(MatchingCallsBatteryAssertion.assertHelperMatchingCalls.selector);
        target.driver();
    }
}
