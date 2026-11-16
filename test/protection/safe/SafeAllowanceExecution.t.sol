// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MultiSend} from "../../../lib/safe-smart-account/contracts/libraries/MultiSend.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SafeTxShapeAssertion} from "../../../src/protection/safe/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../../src/protection/safe/SafeTxShapeHelpers.sol";

// Executes the module-entrypoint ABI, without modeling Safe authorization or proxy dispatch.
contract AllowanceExecutionCaller {
    function execTransactionFromModule(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        returns (bool success)
    {
        if (operation == 0) (success,) = to.call{value: value}(data);
        else (success,) = to.delegatecall(data);
        require(success, "execution failed");
    }
}

contract SpendableAllowanceToken is ERC20 {
    constructor(address owner) ERC20("Allowance test", "TEST") {
        _mint(owner, 1_000);
    }

    function increaseAllowance(address spender, uint256 added) external returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + added);
        return true;
    }
}

contract AllowanceExecutionSpender {
    function spend(SpendableAllowanceToken token, address owner, uint256 amount) external {
        require(token.transferFrom(owner, address(this), amount));
    }
}

contract SafeAllowanceExecutionTest is Test, CredibleTest {
    AllowanceExecutionCaller internal caller;
    SpendableAllowanceToken internal token;
    SpendableAllowanceToken internal otherToken;
    AllowanceExecutionSpender internal spender;
    AllowanceExecutionSpender internal otherSpender;
    MultiSend internal multiSend;

    function setUp() public {
        caller = new AllowanceExecutionCaller();
        token = new SpendableAllowanceToken(address(caller));
        otherToken = new SpendableAllowanceToken(address(caller));
        spender = new AllowanceExecutionSpender();
        otherSpender = new AllowanceExecutionSpender();
        multiSend = new MultiSend();
    }

    function testOverCapGrantSpendRevokeRollsBackTokens() public {
        _arm(100, false);
        vm.expectRevert(_aboveCap(120));
        _batch(bytes.concat(_increase(60), _increase(60), _spend(120), _approve(0)));
        _assertBalances(0, 0);
    }

    function testAtCapGrantSpendRevokeSucceeds() public {
        _arm(100, false);
        _batch(bytes.concat(_increase(37), _increase(63), _spend(90), _approve(0)));
        _assertBalances(90, 0);
    }

    function testFuzzSpendingAndResetsDoNotReplenishBound(uint8 seed, uint8 first, uint8 second, bool reset) public {
        uint256 initial = bound(seed, 0, 100);
        uint256 a = bound(first, 1, 100);
        uint256 b = bound(second, 1, 100);
        _direct(abi.encodeCall(token.approve, (address(spender), initial)));
        bytes memory actions = bytes.concat(
            _increase(a), _spend(initial + a), reset ? _approve(0) : bytes(""), _increase(b), _spend(b), _approve(0)
        );
        _arm(100, false);
        bool blocked = initial + a + b > 100;
        if (blocked) vm.expectRevert();
        _batch(actions);
        _assertBalances(blocked ? 0 : initial + a + b, blocked ? initial : 0);
    }

    function testResetWithoutSpendingDoesNotReplenishBound() public {
        _arm(100, false);
        vm.expectRevert(_aboveCap(120));
        _batch(bytes.concat(_increase(60), _approve(0), _increase(60), _approve(0)));
        _assertBalances(0, 0);
    }

    function testStandaloneRevocationOfExcessiveAllowanceSucceeds() public {
        _direct(abi.encodeCall(token.approve, (address(spender), type(uint256).max)));
        _arm(100, false);
        _direct(abi.encodeCall(token.approve, (address(spender), 0)));
        _assertBalances(0, 0);
        // A subsequent entrypoint starts a fresh bound after recovery.
        _arm(100, false);
        _direct(abi.encodeCall(token.increaseAllowance, (address(spender), 100)));
        _assertBalances(0, 100);
    }

    function testResetBeforeIncreaseRetainsStartingAllowance() public {
        _direct(abi.encodeCall(token.approve, (address(spender), 90)));
        _arm(100, false);
        vm.expectRevert(_aboveCap(110));
        _batch(bytes.concat(_approve(0), _increase(20)));
        _assertBalances(0, 90);
    }

    function testZeroMethodsDoNotBlockOtherwiseValidBatch() public {
        _direct(abi.encodeCall(token.approve, (address(spender), 37)));
        _arm(100, false);
        _batch(bytes.concat(_approve(0), _increase(0), _increase(63), _approve(0)));
        _assertBalances(0, 0);

        _arm(100, false);
        _batch(bytes.concat(_approve(40), _increase(0), _approve(0)));
        _assertBalances(0, 0);
    }

    function testApproveThenIncreaseSamePairBlocked() public {
        _arm(100, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTxShapeHelpers.SafeTxShapeMixedApprovalMethodsBlocked.selector, address(token), address(spender)
            )
        );
        _batch(bytes.concat(_approve(40), _approve(0), _increase(20)));
        _assertBalances(0, 0);
    }

    function testIncreaseThenApproveSamePairBlocked() public {
        _arm(100, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTxShapeHelpers.SafeTxShapeMixedApprovalMethodsBlocked.selector, address(token), address(spender)
            )
        );
        _batch(bytes.concat(_increase(20), _approve(0), _approve(40)));
        _assertBalances(0, 0);
    }

    function testDifferentSpendersDoNotMixMethodsOrShareBounds() public {
        _arm(100, false);
        _batch(
            bytes.concat(
                _approve(90),
                _action(address(token), abi.encodeCall(token.increaseAllowance, (address(otherSpender), 31))),
                _action(address(token), abi.encodeCall(token.increaseAllowance, (address(otherSpender), 69)))
            )
        );
        assertEq(token.allowance(address(caller), address(spender)), 90);
        assertEq(token.allowance(address(caller), address(otherSpender)), 100);
    }

    function testDifferentTokensDoNotMixMethodsOrShareBounds() public {
        _arm(100, false);
        _batch(
            bytes.concat(
                _increase(100), _action(address(otherToken), abi.encodeCall(otherToken.approve, (address(spender), 73)))
            )
        );
        assertEq(token.allowance(address(caller), address(spender)), 100);
        assertEq(otherToken.allowance(address(caller), address(spender)), 73);
    }

    function testIncreaseBoundsAreIndependentAcrossPairs() public {
        _arm(100, false);
        _batch(
            bytes.concat(
                _increase(100),
                _action(address(token), abi.encodeCall(token.increaseAllowance, (address(otherSpender), 83))),
                _action(address(otherToken), abi.encodeCall(otherToken.increaseAllowance, (address(spender), 97)))
            )
        );
        assertEq(token.allowance(address(caller), address(spender)), 100);
        assertEq(token.allowance(address(caller), address(otherSpender)), 83);
        assertEq(otherToken.allowance(address(caller), address(spender)), 97);
    }

    function testPureApprovalsRemainAllowanceCapsNotSpendingBudgets() public {
        _arm(100, false);
        _batch(bytes.concat(_approve(90), _spend(90), _approve(80), _spend(80), _approve(0)));
        _assertBalances(170, 0);
    }

    function testSaturatedCumulativeBoundRequiresUnlimitedOptIn() public {
        _arm(type(uint256).max, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTxShapeHelpers.SafeTxShapeApprovalUnlimitedBlocked.selector,
                address(token),
                address(spender),
                uint8(2)
            )
        );
        _batch(bytes.concat(_increase(type(uint256).max - 2), _approve(0), _increase(10)));
        _assertBalances(0, 0);
    }

    function testSaturatedCumulativeBoundAllowedWithOptIn() public {
        _arm(type(uint256).max, true);
        _batch(bytes.concat(_increase(type(uint256).max - 2), _approve(0), _increase(10)));
        _assertBalances(0, 10);
    }

    function testStartingAllowancePlusCumulativeBoundSaturates() public {
        _direct(abi.encodeCall(token.approve, (address(spender), 7)));
        _arm(type(uint256).max, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTxShapeHelpers.SafeTxShapeApprovalUnlimitedBlocked.selector,
                address(token),
                address(spender),
                uint8(2)
            )
        );
        _batch(bytes.concat(_increase(type(uint256).max - 8), _approve(0), _increase(9)));
        _assertBalances(0, 7);
    }

    function testDirectMaximumAllowanceBlockedDespiteMaximumCap() public {
        _arm(type(uint256).max, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeTxShapeHelpers.SafeTxShapeApprovalUnlimitedBlocked.selector,
                address(token),
                address(spender),
                uint8(2)
            )
        );
        _direct(abi.encodeCall(token.increaseAllowance, (address(spender), type(uint256).max)));
        _assertBalances(0, 0);
    }

    function testUnlimitedOptInDoesNotLiftFiniteCap() public {
        _arm(100, true);
        vm.expectRevert(_aboveCap(101));
        _direct(abi.encodeCall(token.increaseAllowance, (address(spender), 101)));
        _assertBalances(0, 0);
    }

    function testUnlimitedOptInAllowsSentinelWithFiniteCap() public {
        _arm(100, true);
        _direct(abi.encodeCall(token.increaseAllowance, (address(spender), type(uint256).max)));
        _assertBalances(0, type(uint256).max);
    }

    function _arm(uint256 cap, bool allowUnlimited) internal {
        SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
        targets[0] = SafeTxShapeHelpers.TargetPolicy(address(token), true, false, false, false);
        SafeTxShapeHelpers.ApprovalPolicy[] memory approvals = new SafeTxShapeHelpers.ApprovalPolicy[](6);
        for (uint256 i; i < 3; ++i) {
            address t = i == 2 ? address(otherToken) : address(token);
            address s = i == 1 ? address(otherSpender) : address(spender);
            approvals[2 * i] = SafeTxShapeHelpers.ApprovalPolicy(t, s, 1, cap, allowUnlimited);
            approvals[2 * i + 1] = SafeTxShapeHelpers.ApprovalPolicy(t, s, 2, cap, allowUnlimited);
        }
        SafeTxShapeHelpers.BatchExecutorPolicy[] memory batches = new SafeTxShapeHelpers.BatchExecutorPolicy[](1);
        batches[0] =
            SafeTxShapeHelpers.BatchExecutorPolicy(address(multiSend), MultiSend.multiSend.selector, true, 6, false);
        cl.assertion(
            address(caller),
            abi.encodePacked(
                type(SafeTxShapeAssertion).creationCode,
                abi.encode(
                    targets,
                    new SafeTxShapeHelpers.SelectorPolicy[](0),
                    batches,
                    approvals,
                    false,
                    new address[](0),
                    new address[](0)
                )
            ),
            SafeTxShapeAssertion.assertSafeApprovalPolicy.selector
        );
    }

    function _direct(bytes memory data) internal {
        caller.execTransactionFromModule(address(token), 0, data, 0);
    }

    function _batch(bytes memory actions) internal {
        caller.execTransactionFromModule(address(multiSend), 0, abi.encodeCall(multiSend.multiSend, (actions)), 1);
    }

    function _increase(uint256 amount) internal view returns (bytes memory) {
        return _action(address(token), abi.encodeCall(token.increaseAllowance, (address(spender), amount)));
    }

    function _approve(uint256 amount) internal view returns (bytes memory) {
        return _action(address(token), abi.encodeCall(token.approve, (address(spender), amount)));
    }

    function _spend(uint256 amount) internal view returns (bytes memory) {
        return _action(address(spender), abi.encodeCall(spender.spend, (token, address(caller), amount)));
    }

    function _action(address target, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), target, uint256(0), data.length, data);
    }

    function _aboveCap(uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            SafeTxShapeHelpers.SafeTxShapeApprovalAmountAboveCap.selector,
            address(token),
            address(spender),
            uint8(2),
            amount,
            uint256(100)
        );
    }

    function _assertBalances(uint256 spent, uint256 allowance) internal view {
        assertEq(token.balanceOf(address(caller)), 1_000 - spent);
        assertEq(token.balanceOf(address(spender)), spent);
        assertEq(token.allowance(address(caller), address(spender)), allowance);
    }
}
