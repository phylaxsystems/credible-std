// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Assertion} from "../../../src/Assertion.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {TydroProtectionSuite, ITydroL2Pool} from "../src/TydroOperationSafety.sol";

contract TydroCompactBorrowAssertion is Assertion {
    uint256 internal constant L2_SHORTENED_AMOUNT_MASK = type(uint128).max;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertCompactBorrowIsZeroAmount.selector, ITydroL2Pool.borrow.selector);
    }

    function assertCompactBorrowIsZeroAmount() external view {
        bytes memory input = ph.callinputAt(ph.context().callStart);
        bytes32 args = abi.decode(_stripSelector(input), (bytes32));
        uint256 amount = (uint256(args) >> 16) & L2_SHORTENED_AMOUNT_MASK;

        require(amount == 0, "Tydro: compact borrow amount nonzero");
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "Tydro: short call input");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}

contract MockTydroPool is ITydroL2Pool {
    address[] internal reserves;

    constructor(address reserve) {
        reserves.push(reserve);
    }

    function getReservesList() external view returns (address[] memory) {
        return reserves;
    }

    function borrow(bytes32) external override {}

    function withdraw(bytes32) external pure override returns (uint256) {
        return 0;
    }

    function liquidationCall(bytes32, bytes32) external pure override {}

    function setUserUseReserveAsCollateral(bytes32) external pure override {}
}

contract TydroOperationSafetyTest is Test, CredibleTest {
    MockTydroPool internal pool;
    address internal reserve = makeAddr("reserve");
    address internal addressesProvider = makeAddr("addressesProvider");

    function setUp() public {
        pool = new MockTydroPool(reserve);
    }

    function testCompactSelectorsAreIncluded() public {
        TydroProtectionSuite suite = new TydroProtectionSuite(address(pool), addressesProvider);
        bytes4[] memory selectors = suite.getMonitoredSelectors();

        assertEq(selectors.length, 10);
        assertEq(selectors[6], ITydroL2Pool.borrow.selector);
        assertEq(selectors[7], ITydroL2Pool.withdraw.selector);
        assertEq(selectors[8], ITydroL2Pool.liquidationCall.selector);
        assertEq(selectors[9], ITydroL2Pool.setUserUseReserveAsCollateral.selector);
    }

    function testZeroAmountCompactBorrowPasses() public {
        bytes memory createData = abi.encodePacked(type(TydroCompactBorrowAssertion).creationCode);
        cl.assertion(address(pool), createData, TydroCompactBorrowAssertion.assertCompactBorrowIsZeroAmount.selector);

        pool.borrow(bytes32(0));
    }

    function testNonzeroAmountCompactBorrowTrips() public {
        bytes memory createData = abi.encodePacked(type(TydroCompactBorrowAssertion).creationCode);
        cl.assertion(address(pool), createData, TydroCompactBorrowAssertion.assertCompactBorrowIsZeroAmount.selector);

        bytes32 args = bytes32(uint256(1) << 16);
        vm.expectRevert(bytes("Tydro: compact borrow amount nonzero"));
        pool.borrow(args);
    }
}
