// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SafeTxShapeAssertion} from "../src/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../src/SafeTxShapeHelpers.sol";

contract MockSafe {
    function execTransaction(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address,
        bytes calldata
    ) external pure returns (bool success) {
        return true;
    }
}

contract SafeTxShapeAssertionTest is Test, CredibleTest {
    MockSafe internal safe;
    address internal allowedTarget = makeAddr("allowedTarget");
    address internal blockedTarget = makeAddr("blockedTarget");

    function setUp() public {
        safe = new MockSafe();
    }

    function _arm() internal {
        bytes memory createData =
            abi.encodePacked(type(SafeTxShapeAssertion).creationCode, _safeTxShapeConstructorArgs());
        cl.assertion(address(safe), createData, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);
    }

    function _safeTxShapeConstructorArgs() internal view returns (bytes memory) {
        return abi.encode(
            _targetPolicies(),
            new SafeTxShapeHelpers.SelectorPolicy[](0),
            new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
            new SafeTxShapeHelpers.ApprovalPolicy[](0),
            false,
            new address[](0)
        );
    }

    function _targetPolicies() internal view returns (SafeTxShapeHelpers.TargetPolicy[] memory policies) {
        policies = new SafeTxShapeHelpers.TargetPolicy[](1);
        policies[0] = SafeTxShapeHelpers.TargetPolicy({
            target: allowedTarget,
            allowAnySelector: true,
            allowEmptyCalldata: false,
            allowFallbackCalldata: false,
            allowNonzeroValue: false
        });
    }

    function _execSafeTx(address to) internal returns (bool) {
        return safe.execTransaction(to, 0, abi.encodeWithSelector(bytes4(0x12345678)), 0, 0, 0, 0, address(0), address(0), "");
    }

    function testConfiguredTargetPasses() public {
        _arm();
        assertTrue(_execSafeTx(allowedTarget));
    }

    function testUnknownTargetTrips() public {
        _arm();
        vm.expectRevert(abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeUnknownTarget.selector, blockedTarget));
        _execSafeTx(blockedTarget);
    }
}
