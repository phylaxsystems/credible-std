// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {LlamaLendControllerAssertion} from "../../../src/protection/lending/examples/curve/LlamaLendControllerAssertion.sol";
import {CurveLlammaAssertion} from "../../../src/protection/swaps/examples/curve-stablecoin/CurveLlammaAssertion.sol";

contract MockLlamaLendController {
    address internal immutable borrowedToken;

    constructor(address borrowedToken_) {
        borrowedToken = borrowedToken_;
    }

    function borrowed_token() external view returns (address) {
        return borrowedToken;
    }

    function available_balance() external pure returns (uint256) {
        return 0;
    }

    function total_debt() external pure returns (uint256) {
        return 0;
    }

    function borrow_cap() external pure returns (uint256) {
        return type(uint256).max;
    }
}

contract MockCurveLlammaAmm {
    address internal immutable borrowedToken;
    address internal immutable collateralToken;

    constructor(address borrowedToken_, address collateralToken_) {
        borrowedToken = borrowedToken_;
        collateralToken = collateralToken_;
    }

    function coins(uint256 i) external view returns (address) {
        if (i == 0) {
            return borrowedToken;
        }
        if (i == 1) {
            return collateralToken;
        }
        revert("MockCurveLlammaAmm: bad coin index");
    }

    function active_band() external pure returns (int256) {
        return 0;
    }

    function min_band() external pure returns (int256) {
        return 0;
    }

    function max_band() external pure returns (int256) {
        return 0;
    }

    function bands_x(int256) external pure returns (uint256) {
        return 0;
    }

    function bands_y(int256) external pure returns (uint256) {
        return 0;
    }

    function get_p() external pure returns (uint256) {
        return 1e18;
    }

    function p_current_down(int256) external pure returns (uint256) {
        return 1e18;
    }

    function p_current_up(int256) external pure returns (uint256) {
        return 1e18;
    }
}

contract CurveInflowAssertionsTest is Test {
    function testLlamaLendControllerAssertionDeploysWithCumulativeInflowBreaker() external {
        ERC20Mock borrowedToken = new ERC20Mock();
        MockLlamaLendController controller = new MockLlamaLendController(address(borrowedToken));

        LlamaLendControllerAssertion assertion = new LlamaLendControllerAssertion(address(controller), 0);

        assertTrue(address(assertion) != address(0));
        assertEq(assertion.INFLOW_THRESHOLD_BPS(), 1_000);
        assertEq(assertion.INFLOW_WINDOW_DURATION(), 6 hours);
        assertEq(assertion.OUTFLOW_THRESHOLD_BPS(), 1_000);
        assertEq(assertion.OUTFLOW_WINDOW_DURATION(), 24 hours);
    }

    function testCurveLlammaAssertionDeploysWithCumulativeInflowBreaker() external {
        ERC20Mock borrowedToken = new ERC20Mock();
        ERC20Mock collateralToken = new ERC20Mock();
        MockCurveLlammaAmm amm = new MockCurveLlammaAmm(address(borrowedToken), address(collateralToken));

        CurveLlammaAssertion assertion = new CurveLlammaAssertion(address(amm), 1, 1, 1, 0, 0);

        assertTrue(address(assertion) != address(0));
        assertEq(assertion.INFLOW_THRESHOLD_BPS(), 1_000);
        assertEq(assertion.INFLOW_WINDOW_DURATION(), 6 hours);
    }
}
