// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SafeTxShapeAssertion} from "../../../src/protection/safe/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../../src/protection/safe/SafeTxShapeHelpers.sol";

contract MockSafeTxShapeTarget {
    function execTransaction(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory
    ) external payable returns (bool success) {
        return true;
    }

    function execTransactionFromModule(address, uint256, bytes memory, uint8) external pure returns (bool success) {
        return true;
    }

    function execTransactionFromModuleReturnData(address, uint256, bytes memory, uint8)
        external
        pure
        returns (bool success, bytes memory returnData)
    {
        return (true, "");
    }
}

contract MockProtocolTarget {
    function doThing(uint256) external {}
    function otherThing() external {}
    function payableThing() external payable {}

    fallback() external payable {}
    receive() external payable {}
}

contract MockApprovalTarget {
    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function increaseAllowance(address, uint256) external pure returns (bool) {
        return true;
    }

    function setApprovalForAll(address, bool) external pure {}
}

contract MockMultiSendExecutor {
    function multiSend(bytes memory) external payable {}
}

contract SafeTxShapeAssertionTest is Test, CredibleTest {
    uint8 internal constant OP_CALL = 0;
    uint8 internal constant OP_DELEGATECALL = 1;
    uint8 internal constant OP_UNKNOWN = 2;

    uint8 internal constant APPROVAL_KIND_ERC20_APPROVE = 1;
    uint8 internal constant APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE = 2;
    uint8 internal constant APPROVAL_KIND_ERC721_APPROVE = 3;
    uint8 internal constant APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL = 4;
    uint8 internal constant APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL = 5;

    bytes4 internal constant MULTISEND_SELECTOR = bytes4(keccak256("multiSend(bytes)"));
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = bytes4(keccak256("increaseAllowance(address,uint256)"));

    address internal constant MODULE = address(0xA001);
    address internal constant OTHER_MODULE = address(0xB002);
    address internal constant TRUSTED_SPENDER = address(0x5001);
    address internal constant TRUSTED_OPERATOR = address(0x5002);
    address internal constant UNTRUSTED = address(0xDEAD);

    MockSafeTxShapeTarget internal safe;
    MockProtocolTarget internal target;
    MockProtocolTarget internal emptyTarget;
    MockProtocolTarget internal payableTarget;
    MockApprovalTarget internal erc20Token;
    MockApprovalTarget internal erc721Token;
    MockApprovalTarget internal erc1155Token;
    MockMultiSendExecutor internal multiSend;

    function setUp() public {
        safe = new MockSafeTxShapeTarget();
        target = new MockProtocolTarget();
        emptyTarget = new MockProtocolTarget();
        payableTarget = new MockProtocolTarget();
        erc20Token = new MockApprovalTarget();
        erc721Token = new MockApprovalTarget();
        erc1155Token = new MockApprovalTarget();
        multiSend = new MockMultiSendExecutor();
    }

    function testAllowsOwnerTransactionToKnownTargetAndSelector() public {
        _assertOwnerAllowedByAllBaselinePolicies(
            false, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL
        );
    }

    function testAllowsModuleTransactionFromAllowlistedModule() public {
        _assertModuleAllowedByAllBaselinePolicies(
            address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL
        );
    }

    function testAllowsModuleTransactionReturnDataFromAllowlistedModule() public {
        _assertModuleReturnDataAllowedByAllBaselinePolicies(
            address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL
        );
    }

    function testAllowsMultiSendBatchWithKnownInnerActions() public {
        SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
        targets[0] = _targetPolicy(address(target), false, false, false, false);

        SafeTxShapeHelpers.SelectorPolicy[] memory selectors = new SafeTxShapeHelpers.SelectorPolicy[](1);
        selectors[0] = _selectorPolicy(address(target), MockProtocolTarget.doThing.selector, false);

        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));

        _assertOwnerAllowedByAllPolicies(
            targets,
            selectors,
            _baselineBatchPolicies(4),
            new SafeTxShapeHelpers.ApprovalPolicy[](0),
            false,
            _noModules(),
            address(multiSend),
            0,
            abi.encodeWithSelector(MULTISEND_SELECTOR, txs),
            OP_DELEGATECALL
        );
    }

    function testAllowsCallBasedMultiSendBatchWithKnownInnerActions() public {
        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));

        _assertOwnerAllowedByAllBaselinePolicies(
            false, address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_CALL
        );
    }

    function testAllowsErc20ApprovalToTrustedSpenderUnderCap() public {
        _assertOwnerAllowedByAllBaselinePolicies(
            false, address(erc20Token), 0, abi.encodeCall(MockApprovalTarget.approve, (TRUSTED_SPENDER, 75)), OP_CALL
        );
    }

    function testAllowsErc20ApprovalResetToZero() public {
        _assertOwnerAllowedByAllBaselinePolicies(
            false, address(erc20Token), 0, abi.encodeCall(MockApprovalTarget.approve, (UNTRUSTED, 0)), OP_CALL
        );
    }

    function testAllowsErc20UnlimitedApprovalWhenExplicitlyAllowed() public {
        _assertOwnerAllowedByAllPolicies(
            _baselineTargets(),
            _baselineSelectors(),
            _baselineBatchPolicies(4),
            _approvalPolicies(true),
            false,
            _noModules(),
            address(erc20Token),
            0,
            abi.encodeCall(MockApprovalTarget.approve, (TRUSTED_SPENDER, type(uint256).max)),
            OP_CALL
        );
    }

    function testAllowsErc721AndErc1155OperatorRevocation() public {
        _assertOwnerAllowedByAllBaselinePolicies(
            false,
            address(erc721Token),
            0,
            abi.encodeCall(MockApprovalTarget.setApprovalForAll, (UNTRUSTED, false)),
            OP_CALL
        );
        _assertOwnerAllowedByAllBaselinePolicies(
            false,
            address(erc1155Token),
            0,
            abi.encodeCall(MockApprovalTarget.setApprovalForAll, (UNTRUSTED, false)),
            OP_CALL
        );
    }

    function testAllowsDirectEmptyCalldataWhenPolicyPermitsIt() public {
        _assertOwnerAllowedByAllBaselinePolicies(false, address(emptyTarget), 0, "", OP_CALL);
    }

    function testAllowsMultiSendInnerEmptyCalldataWhenPolicyPermitsIt() public {
        bytes memory txs = _packMultiSendTx(OP_CALL, address(emptyTarget), 0, "");

        _assertOwnerAllowedByAllBaselinePolicies(
            false, address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL
        );
    }

    function testBlocksOwnerTransactionToUnknownTargetWithCalldata() public {
        MockProtocolTarget unknownTarget = new MockProtocolTarget();
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(unknownTarget), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL);
    }

    function testBlocksOwnerTransactionWithSignedGasRefund() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeModulePolicy.selector);

        vm.expectRevert();
        _execOwnerWithGasPrice(address(target), abi.encodeCall(MockProtocolTarget.doThing, (1)), 1);
    }

    function testBlocksModuleTransactionToUnknownTargetWithCalldata() public {
        MockProtocolTarget unknownTarget = new MockProtocolTarget();
        _armBaselinePolicyFor(true, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        vm.prank(MODULE);
        safe.execTransactionFromModule(
            address(unknownTarget), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL
        );
    }

    function testBlocksModuleExecutionWhenDisabled() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeModulePolicy.selector);

        vm.expectRevert();
        vm.prank(MODULE);
        safe.execTransactionFromModule(address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL);
    }

    function testBlocksUnallowlistedModule() public {
        _armBaselinePolicyFor(true, SafeTxShapeAssertion.assertSafeModulePolicy.selector);

        vm.expectRevert();
        vm.prank(OTHER_MODULE);
        safe.execTransactionFromModule(address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL);
    }

    function testBlocksKnownTargetWithUnknownSelector() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 0, abi.encodeCall(MockProtocolTarget.otherThing, ()), OP_CALL);
    }

    function testBlocksCalldataShorterThanSelector() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 0, hex"010203", OP_CALL);
    }

    function testBlocksEmptyCalldataWhenPolicyDoesNotPermitIt() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 0, "", OP_CALL);
    }

    function testBlocksZeroAddressTarget() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(0), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL);
    }

    function testBlocksNativeValueForSelectorWithoutValuePolicy() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 1, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_CALL);
    }

    function testBlocksDirectDelegatecall() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_DELEGATECALL);
    }

    function testBlocksModuleDelegatecall() public {
        _armBaselinePolicyFor(true, SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);

        vm.expectRevert();
        vm.prank(MODULE);
        safe.execTransactionFromModule(
            address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_DELEGATECALL
        );
    }

    function testBlocksUnknownOperation() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)), OP_UNKNOWN);
    }

    function testBlocksTopLevelDelegatecallToNonBatchTarget() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);

        vm.expectRevert();
        _execOwner(address(target), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, ""), OP_DELEGATECALL);
    }

    function testBlocksTopLevelMultiSendThroughUnapprovedExecutor() public {
        MockMultiSendExecutor unapproved = new MockMultiSendExecutor();
        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);

        vm.expectRevert();
        _execOwner(address(unapproved), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksMalformedMultiSendPayload() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeBatchPolicy.selector);

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, hex"01"), OP_DELEGATECALL);
    }

    function testBlocksUnpaddedMultiSendAbiPayload() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeBatchPolicy.selector);

        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));
        bytes memory malformed = abi.encodePacked(MULTISEND_SELECTOR, uint256(32), txs.length, txs);

        vm.expectRevert();
        _execOwner(address(multiSend), 0, malformed, OP_DELEGATECALL);
    }

    function testBlocksMultiSendTrailingBytes() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeBatchPolicy.selector);

        bytes memory txs = bytes.concat(
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1))), hex"99"
        );

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksMultiSendUnknownOperation() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeBatchPolicy.selector);

        bytes memory txs =
            _packMultiSendTx(OP_UNKNOWN, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksMultiSendUnknownInnerTarget() public {
        MockProtocolTarget unknownTarget = new MockProtocolTarget();
        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(unknownTarget), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksCallBasedMultiSendUnknownInnerTarget() public {
        MockProtocolTarget unknownTarget = new MockProtocolTarget();
        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(unknownTarget), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_CALL);
    }

    function testBlocksMultiSendZeroAddressTarget() public {
        bytes memory txs = _packMultiSendTx(OP_CALL, address(0), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        vm.expectRevert(abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeUnknownTarget.selector, address(0)));
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksMultiSendKnownTargetUnknownSelector() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector);

        bytes memory txs =
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.otherThing, ()));

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksMultiSendInnerDelegatecall() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);

        bytes memory txs =
            _packMultiSendTx(OP_DELEGATECALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)));

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksNestedMultiSend() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeBatchPolicy.selector);

        bytes memory nested = abi.encodeWithSelector(
            MULTISEND_SELECTOR,
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1)))
        );
        bytes memory txs = _packMultiSendTx(OP_CALL, address(multiSend), 0, nested);

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksMaxBatchActionCountExceeded() public {
        _armPolicyFor(
            _baselineTargets(),
            _baselineSelectors(),
            _baselineBatchPolicies(1),
            _approvalPolicies(false),
            false,
            _noModules(),
            SafeTxShapeAssertion.assertSafeBatchPolicy.selector
        );

        bytes memory txs = bytes.concat(
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (1))),
            _packMultiSendTx(OP_CALL, address(target), 0, abi.encodeCall(MockProtocolTarget.doThing, (2)))
        );

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksErc20ApprovalToUntrustedSpender() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(address(erc20Token), 0, abi.encodeCall(MockApprovalTarget.approve, (UNTRUSTED, 1)), OP_CALL);
    }

    function testBlocksErc20UnlimitedApprovalUnlessExplicitlyAllowed() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(
            address(erc20Token),
            0,
            abi.encodeCall(MockApprovalTarget.approve, (TRUSTED_SPENDER, type(uint256).max)),
            OP_CALL
        );
    }

    function testBlocksErc20ApprovalOverCap() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(address(erc20Token), 0, abi.encodeCall(MockApprovalTarget.approve, (TRUSTED_SPENDER, 101)), OP_CALL);
    }

    function testBlocksErc20IncreaseAllowanceToUntrustedSpender() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(
            address(erc20Token), 0, abi.encodeWithSelector(INCREASE_ALLOWANCE_SELECTOR, UNTRUSTED, uint256(1)), OP_CALL
        );
    }

    function testBlocksZeroAddressSpenderForRiskIncreasingApproval() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(address(erc20Token), 0, abi.encodeCall(MockApprovalTarget.approve, (address(0), 1)), OP_CALL);
    }

    function testBlocksErc721ApproveToUntrustedOperator() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(address(erc721Token), 0, abi.encodeCall(MockApprovalTarget.approve, (UNTRUSTED, 1)), OP_CALL);
    }

    function testBlocksErc721SetApprovalForAllToUntrustedOperator() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(
            address(erc721Token), 0, abi.encodeCall(MockApprovalTarget.setApprovalForAll, (UNTRUSTED, true)), OP_CALL
        );
    }

    function testBlocksErc1155SetApprovalForAllToUntrustedOperator() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        vm.expectRevert();
        _execOwner(
            address(erc1155Token), 0, abi.encodeCall(MockApprovalTarget.setApprovalForAll, (UNTRUSTED, true)), OP_CALL
        );
    }

    function testBlocksApprovalHiddenInsideMultiSend() public {
        _armBaselinePolicyFor(false, SafeTxShapeAssertion.assertSafeApprovalPolicy.selector);

        bytes memory txs = _packMultiSendTx(
            OP_CALL, address(erc20Token), 0, abi.encodeCall(MockApprovalTarget.approve, (UNTRUSTED, 1))
        );

        vm.expectRevert();
        _execOwner(address(multiSend), 0, abi.encodeWithSelector(MULTISEND_SELECTOR, txs), OP_DELEGATECALL);
    }

    function testBlocksDuplicatePolicyEntries() public {
        SafeTxShapeHelpers.TargetPolicy[] memory targets = _baselineTargets();
        targets[1].target = targets[0].target;

        vm.expectRevert();
        new SafeTxShapeAssertion(
            targets, _baselineSelectors(), _baselineBatchPolicies(4), _approvalPolicies(false), false, _noModules()
        );
    }

    function testBlocksEmptyTargetPolicyArray() public {
        vm.expectRevert();
        new SafeTxShapeAssertion(
            new SafeTxShapeHelpers.TargetPolicy[](0),
            new SafeTxShapeHelpers.SelectorPolicy[](0),
            new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
            new SafeTxShapeHelpers.ApprovalPolicy[](0),
            false,
            _noModules()
        );
    }

    function _assertOwnerAllowedByAllBaselinePolicies(
        bool moduleEnabled,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) internal {
        _assertOwnerAllowedByAllPolicies(
            _baselineTargets(),
            _baselineSelectors(),
            _baselineBatchPolicies(4),
            _approvalPolicies(false),
            moduleEnabled,
            moduleEnabled ? _allowedModules() : _noModules(),
            to,
            value,
            data,
            operation
        );
    }

    function _assertOwnerAllowedByAllPolicies(
        SafeTxShapeHelpers.TargetPolicy[] memory targets,
        SafeTxShapeHelpers.SelectorPolicy[] memory selectors,
        SafeTxShapeHelpers.BatchExecutorPolicy[] memory batches,
        SafeTxShapeHelpers.ApprovalPolicy[] memory approvals,
        bool moduleEnabled,
        address[] memory modules,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) internal {
        bytes4[5] memory assertionSelectors = _allAssertionSelectors();
        for (uint256 i; i < assertionSelectors.length; ++i) {
            _armPolicyFor(targets, selectors, batches, approvals, moduleEnabled, modules, assertionSelectors[i]);
            _execOwner(to, value, data, operation);
        }
    }

    function _assertModuleAllowedByAllBaselinePolicies(address to, uint256 value, bytes memory data, uint8 operation)
        internal
    {
        bytes4[5] memory assertionSelectors = _allAssertionSelectors();
        for (uint256 i; i < assertionSelectors.length; ++i) {
            _armBaselinePolicyFor(true, assertionSelectors[i]);
            vm.prank(MODULE);
            safe.execTransactionFromModule(to, value, data, operation);
        }
    }

    function _assertModuleReturnDataAllowedByAllBaselinePolicies(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) internal {
        bytes4[5] memory assertionSelectors = _allAssertionSelectors();
        for (uint256 i; i < assertionSelectors.length; ++i) {
            _armBaselinePolicyFor(true, assertionSelectors[i]);
            vm.prank(MODULE);
            safe.execTransactionFromModuleReturnData(to, value, data, operation);
        }
    }

    function _armBaselinePolicyFor(bool moduleEnabled, bytes4 assertionSelector) internal {
        _armPolicyFor(
            _baselineTargets(),
            _baselineSelectors(),
            _baselineBatchPolicies(4),
            _approvalPolicies(false),
            moduleEnabled,
            moduleEnabled ? _allowedModules() : _noModules(),
            assertionSelector
        );
    }

    function _armPolicyFor(
        SafeTxShapeHelpers.TargetPolicy[] memory targets,
        SafeTxShapeHelpers.SelectorPolicy[] memory selectors,
        SafeTxShapeHelpers.BatchExecutorPolicy[] memory batches,
        SafeTxShapeHelpers.ApprovalPolicy[] memory approvals,
        bool moduleEnabled,
        address[] memory modules,
        bytes4 assertionSelector
    ) internal {
        bytes memory createData = abi.encodePacked(
            type(SafeTxShapeAssertion).creationCode,
            abi.encode(targets, selectors, batches, approvals, moduleEnabled, modules)
        );

        _armAssertion(createData, assertionSelector);
    }

    function _allAssertionSelectors() internal pure returns (bytes4[5] memory assertionSelectors) {
        assertionSelectors[0] = SafeTxShapeAssertion.assertSafeModulePolicy.selector;
        assertionSelectors[1] = SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector;
        assertionSelectors[2] = SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector;
        assertionSelectors[3] = SafeTxShapeAssertion.assertSafeBatchPolicy.selector;
        assertionSelectors[4] = SafeTxShapeAssertion.assertSafeApprovalPolicy.selector;
    }

    function _armAssertion(bytes memory createData, bytes4 assertionSelector) internal {
        cl.assertion(address(safe), createData, assertionSelector);
    }

    function _execOwner(address to, uint256 value, bytes memory data, uint8 operation) internal {
        safe.execTransaction(to, value, data, operation, 0, 0, 0, address(0), payable(address(0)), "");
    }

    function _execOwnerWithGasPrice(address to, bytes memory data, uint256 gasPrice) internal {
        safe.execTransaction(to, 0, data, OP_CALL, 0, 0, gasPrice, address(0), payable(address(0)), "");
    }

    function _baselineTargets() internal view returns (SafeTxShapeHelpers.TargetPolicy[] memory targets) {
        targets = new SafeTxShapeHelpers.TargetPolicy[](6);
        targets[0] = _targetPolicy(address(target), false, false, false, false);
        targets[1] = _targetPolicy(address(emptyTarget), false, true, false, false);
        targets[2] = _targetPolicy(address(payableTarget), false, false, false, true);
        targets[3] = _targetPolicy(address(erc20Token), false, false, false, false);
        targets[4] = _targetPolicy(address(erc721Token), false, false, false, false);
        targets[5] = _targetPolicy(address(erc1155Token), false, false, false, false);
    }

    function _baselineSelectors() internal view returns (SafeTxShapeHelpers.SelectorPolicy[] memory selectors) {
        selectors = new SafeTxShapeHelpers.SelectorPolicy[](8);
        selectors[0] = _selectorPolicy(address(target), MockProtocolTarget.doThing.selector, false);
        selectors[1] = _selectorPolicy(address(payableTarget), MockProtocolTarget.payableThing.selector, true);
        selectors[2] = _selectorPolicy(address(erc20Token), MockApprovalTarget.approve.selector, false);
        selectors[3] = _selectorPolicy(address(erc20Token), INCREASE_ALLOWANCE_SELECTOR, false);
        selectors[4] = _selectorPolicy(address(erc721Token), MockApprovalTarget.approve.selector, false);
        selectors[5] = _selectorPolicy(address(erc721Token), MockApprovalTarget.setApprovalForAll.selector, false);
        selectors[6] = _selectorPolicy(address(erc1155Token), MockApprovalTarget.setApprovalForAll.selector, false);
        selectors[7] = _selectorPolicy(address(emptyTarget), MockProtocolTarget.doThing.selector, false);
    }

    function _baselineBatchPolicies(uint256 maxActions)
        internal
        view
        returns (SafeTxShapeHelpers.BatchExecutorPolicy[] memory batches)
    {
        batches = new SafeTxShapeHelpers.BatchExecutorPolicy[](1);
        batches[0] = SafeTxShapeHelpers.BatchExecutorPolicy({
            executor: address(multiSend),
            selector: MULTISEND_SELECTOR,
            allowDelegateCall: true,
            maxActions: maxActions,
            allowNested: false
        });
    }

    function _approvalPolicies(bool allowUnlimited)
        internal
        view
        returns (SafeTxShapeHelpers.ApprovalPolicy[] memory approvals)
    {
        approvals = new SafeTxShapeHelpers.ApprovalPolicy[](5);
        approvals[0] =
            _approvalPolicy(address(erc20Token), TRUSTED_SPENDER, APPROVAL_KIND_ERC20_APPROVE, 100, allowUnlimited);
        approvals[1] =
            _approvalPolicy(address(erc20Token), TRUSTED_SPENDER, APPROVAL_KIND_ERC20_INCREASE_ALLOWANCE, 100, false);
        approvals[2] = _approvalPolicy(address(erc721Token), TRUSTED_OPERATOR, APPROVAL_KIND_ERC721_APPROVE, 0, false);
        approvals[3] = _approvalPolicy(
            address(erc721Token), TRUSTED_OPERATOR, APPROVAL_KIND_ERC721_SET_APPROVAL_FOR_ALL, 0, false
        );
        approvals[4] = _approvalPolicy(
            address(erc1155Token), TRUSTED_OPERATOR, APPROVAL_KIND_ERC1155_SET_APPROVAL_FOR_ALL, 0, false
        );
    }

    function _targetPolicy(
        address policyTarget,
        bool allowAnySelector,
        bool allowEmptyCalldata,
        bool allowFallbackCalldata,
        bool allowNonzeroValue
    ) internal pure returns (SafeTxShapeHelpers.TargetPolicy memory policy) {
        policy = SafeTxShapeHelpers.TargetPolicy({
            target: policyTarget,
            allowAnySelector: allowAnySelector,
            allowEmptyCalldata: allowEmptyCalldata,
            allowFallbackCalldata: allowFallbackCalldata,
            allowNonzeroValue: allowNonzeroValue
        });
    }

    function _selectorPolicy(address policyTarget, bytes4 selector, bool allowNonzeroValue)
        internal
        pure
        returns (SafeTxShapeHelpers.SelectorPolicy memory policy)
    {
        policy = SafeTxShapeHelpers.SelectorPolicy({
            target: policyTarget, selector: selector, allowNonzeroValue: allowNonzeroValue
        });
    }

    function _approvalPolicy(address token, address spender, uint8 kind, uint256 maxAmount, bool allowUnlimited)
        internal
        pure
        returns (SafeTxShapeHelpers.ApprovalPolicy memory policy)
    {
        policy = SafeTxShapeHelpers.ApprovalPolicy({
            token: token, spender: spender, kind: kind, maxAmount: maxAmount, allowUnlimited: allowUnlimited
        });
    }

    function _allowedModules() internal pure returns (address[] memory modules) {
        modules = new address[](1);
        modules[0] = MODULE;
    }

    function _noModules() internal pure returns (address[] memory modules) {
        modules = new address[](0);
    }

    function _packMultiSendTx(uint8 operation, address to, uint256 value, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(bytes1(operation), bytes20(to), value, data.length, data);
    }
}
