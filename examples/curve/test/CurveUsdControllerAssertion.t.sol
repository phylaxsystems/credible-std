// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CurveUsdControllerAssertion} from "../src/CurveUsdControllerAssertion.sol";

/// @notice Minimal crvUSD controller exposing only what the tx-end health checks read:
///         `loan_exists`, `health`, and the risk-increasing / liquidation entry points.
contract MockCurveUsdController {
    mapping(address => bool) internal loanExistsFlag;
    mapping(address => int256) internal currentHealth;
    mapping(address => int256) internal pendingHealth;

    /// @notice Seed an account's pre-transaction loan state.
    function setLoan(address user, bool exists, int256 health_) external {
        loanExistsFlag[user] = exists;
        currentHealth[user] = health_;
    }

    /// @notice Health an account lands on after an op that names it executes this tx.
    function setPendingHealth(address user, int256 health_) external {
        pendingHealth[user] = health_;
    }

    function borrow_more(uint256, uint256) external {
        loanExistsFlag[msg.sender] = true;
        currentHealth[msg.sender] = pendingHealth[msg.sender];
    }

    function liquidate(address user, uint256) external {
        currentHealth[user] = pendingHealth[user];
    }

    function loan_exists(address user) external view returns (bool) {
        return loanExistsFlag[user];
    }

    function health(address user, bool) external view returns (int256) {
        return currentHealth[user];
    }
}

contract CurveUsdBorrowBatcher {
    MockCurveUsdController internal immutable CONTROLLER;

    constructor(MockCurveUsdController controller_) {
        CONTROLLER = controller_;
    }

    function twoBorrows() external {
        CONTROLLER.borrow_more(0, 1);
        CONTROLLER.borrow_more(0, 1);
    }
}

contract CurveUsdControllerAssertionTest is Test, CredibleTest {
    MockCurveUsdController internal controller;
    address internal amm = makeAddr("amm");
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        controller = new MockCurveUsdController();
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(CurveUsdControllerAssertion).creationCode, abi.encode(address(controller), amm, uint256(10), uint256(0))
        );
        cl.assertion(address(controller), createData, fnSelector);
    }

    // --- assertPostRiskIncreasingOperationHealth (now onTxEnd, enumerate) ---

    function testRiskIncreasingHealthyPasses() public {
        controller.setPendingHealth(address(this), 1);

        _arm(CurveUsdControllerAssertion.assertPostRiskIncreasingOperationHealth.selector);
        controller.borrow_more(0, 1);
    }

    function testRiskIncreasingUnhealthyTrips() public {
        controller.setPendingHealth(address(this), -1);

        _arm(CurveUsdControllerAssertion.assertPostRiskIncreasingOperationHealth.selector);
        vm.expectRevert(bytes("CurveUSD: unhealthy post-operation"));
        controller.borrow_more(0, 1);
    }

    function testRiskIncreasingFiresOnceForBatchedBorrows() public {
        CurveUsdBorrowBatcher batcher = new CurveUsdBorrowBatcher(controller);
        controller.setPendingHealth(address(batcher), 1);

        _arm(CurveUsdControllerAssertion.assertPostRiskIncreasingOperationHealth.selector);
        // Two borrows by the same account in one tx; health is checked once at tx end.
        batcher.twoBorrows();
    }

    // --- assertPostLiquidationHealthRule (now onTxEnd, enumerate) ---

    function testLiquidationKeepsBorrowerHealthyPasses() public {
        controller.setLoan(borrower, true, 5); // healthy pre-tx
        controller.setPendingHealth(borrower, 2);

        _arm(CurveUsdControllerAssertion.assertPostLiquidationHealthRule.selector);
        controller.liquidate(borrower, 1);
    }

    function testLiquidationLeavingBorrowerUnhealthyTrips() public {
        controller.setLoan(borrower, true, 5); // healthy pre-tx
        controller.setPendingHealth(borrower, -1);

        _arm(CurveUsdControllerAssertion.assertPostLiquidationHealthRule.selector);
        vm.expectRevert(bytes("CurveUSD: healthy liquidation left unhealthy"));
        controller.liquidate(borrower, 1);
    }

    function testLiquidationOfAlreadyUnhealthyBorrowerSkipped() public {
        controller.setLoan(borrower, true, -3); // already unhealthy pre-tx
        controller.setPendingHealth(borrower, -3);

        _arm(CurveUsdControllerAssertion.assertPostLiquidationHealthRule.selector);
        // No revert: the rule only protects borrowers that were healthy at the start of the tx.
        controller.liquidate(borrower, 1);
    }
}
