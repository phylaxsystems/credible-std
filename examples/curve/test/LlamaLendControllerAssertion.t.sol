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

contract LlamaLendBorrowBatcher {
    MockLlamaLendController internal immutable CONTROLLER;

    constructor(MockLlamaLendController controller_) {
        CONTROLLER = controller_;
    }

    function twoBorrows(uint256 debtIncrease) external {
        CONTROLLER.borrow_more(0, debtIncrease);
        CONTROLLER.borrow_more(0, debtIncrease);
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

    function testBatchedBorrowsWithinCapFireOnce() public {
        LlamaLendBorrowBatcher batcher = new LlamaLendBorrowBatcher(controller);

        _arm();
        // Two debt increases in one tx (200 total) stay within the 1000 cap; checked once at tx end.
        batcher.twoBorrows(100 ether);
    }

    function testBatchedBorrowsExceedingCapTripAtTxEnd() public {
        controller.setBorrowCap(150 ether);
        LlamaLendBorrowBatcher batcher = new LlamaLendBorrowBatcher(controller);

        _arm();
        // Net 200 across two borrows exceeds the 150 cap; the single tx-end check still catches it.
        vm.expectRevert(bytes("LlamaLend: borrow cap exceeded"));
        batcher.twoBorrows(100 ether);
    }
}
