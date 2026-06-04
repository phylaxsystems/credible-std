// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {LlamaLendControllerAssertion} from "../src/LlamaLendControllerAssertion.sol";

contract MockLlamaLendController {
    uint256 public totalDebt;
    uint256 public borrowCap = 1_000 ether;

    function setBorrowCap(uint256 borrowCap_) external {
        borrowCap = borrowCap_;
    }

    function borrow_more(uint256, uint256 debtIncrease) external {
        totalDebt += debtIncrease;
    }

    function available_balance() external pure returns (uint256) {
        return 0;
    }

    function total_debt() external view returns (uint256) {
        return totalDebt;
    }

    function borrow_cap() external view returns (uint256) {
        return borrowCap;
    }
}

contract LlamaLendControllerAssertionTest is Test, CredibleTest {
    MockLlamaLendController internal controller;
    address internal borrowedToken = makeAddr("borrowedToken");

    function setUp() public {
        controller = new MockLlamaLendController();
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(LlamaLendControllerAssertion).creationCode, abi.encode(address(controller), borrowedToken, 0)
        );
        cl.assertion(address(controller), createData, LlamaLendControllerAssertion.assertDebtIncreaseWithinBorrowCap.selector);
    }

    function testBorrowMorePassesWithinCap() public {
        _arm();
        controller.borrow_more(0, 100 ether);
    }

    function testBorrowMoreTripsAboveCap() public {
        controller.setBorrowCap(50 ether);

        _arm();
        vm.expectRevert(bytes("LlamaLend: borrow cap exceeded"));
        controller.borrow_more(0, 100 ether);
    }
}
