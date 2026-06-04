// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AaveV4SpokeRiskAssertion} from "../src/AaveV4SpokeRiskAssertion.sol";
import {IAaveV4Spoke} from "../src/AaveV4Interfaces.sol";

/// @notice Minimal Aave v4 Spoke with zero reserves. With `getReserveCount() == 0` the assertion's
///         independent recomputation yields the empty account (health factor = max), so the only
///         thing exercised is the enumerate-at-txEnd path plus the recomputed-vs-reported account
///         comparison — which is exactly the tx-end conversion under test.
contract MockAaveV4Spoke {
    IAaveV4Spoke.UserAccountData internal acct;
    uint256 internal lastPremium;

    constructor() {
        // Matches the recomputed empty account when there are no reserves.
        acct.healthFactor = type(uint256).max;
    }

    function setReportedHealthFactor(uint256 healthFactor) external {
        acct.healthFactor = healthFactor;
    }

    function ORACLE() external view returns (address) {
        return address(this);
    }

    function getReserveCount() external pure returns (uint256) {
        return 0;
    }

    function getUserAccountData(address) external view returns (IAaveV4Spoke.UserAccountData memory) {
        return acct;
    }

    function getUserLastRiskPremium(address) external view returns (uint256) {
        return lastPremium;
    }

    function borrow(uint256, uint256, address) external returns (uint256, uint256) {
        return (0, 0);
    }

    function liquidationCall(uint256, uint256, address, uint256, bool) external {}
}

contract SpokeBorrowBatcher {
    MockAaveV4Spoke internal immutable SPOKE;

    constructor(MockAaveV4Spoke spoke_) {
        SPOKE = spoke_;
    }

    function twoBorrows(address onBehalfOf) external {
        SPOKE.borrow(0, 1, onBehalfOf);
        SPOKE.borrow(0, 1, onBehalfOf);
    }
}

contract AaveV4SpokeRiskAssertionTest is Test, CredibleTest {
    MockAaveV4Spoke internal spoke;
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        spoke = new MockAaveV4Spoke();
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData =
            abi.encodePacked(type(AaveV4SpokeRiskAssertion).creationCode, abi.encode(address(spoke), uint256(4), uint256(100)));
        cl.assertion(address(spoke), createData, fnSelector);
    }

    function testAccountDataMatchesPasses() public {
        _arm(AaveV4SpokeRiskAssertion.assertAccountDataMatchesIndependentState.selector);
        spoke.borrow(0, 1, borrower);
    }

    function testAccountDataMismatchTrips() public {
        // Reported account data diverges from the independent recomputation (HF != max).
        spoke.setReportedHealthFactor(1);

        _arm(AaveV4SpokeRiskAssertion.assertAccountDataMatchesIndependentState.selector);
        vm.expectRevert(bytes("AaveV4Spoke: account health factor mismatch"));
        spoke.borrow(0, 1, borrower);
    }

    function testAccountDataFiresOnceForBatchedBorrows() public {
        SpokeBorrowBatcher batcher = new SpokeBorrowBatcher(spoke);

        _arm(AaveV4SpokeRiskAssertion.assertAccountDataMatchesIndependentState.selector);
        // Two borrows for the same account in one tx; account data is checked once at tx end.
        batcher.twoBorrows(borrower);
    }

    function testLiquidationRuleEnumeratesWithoutReverting() public {
        // With no reserves the recomputed pre-liquidation health is max, so the rule safely skips.
        // Exercises the enumerate path for the liquidation selector at tx end.
        _arm(AaveV4SpokeRiskAssertion.assertLiquidationImprovesBorrowerRisk.selector);
        spoke.liquidationCall(0, 0, borrower, 1, false);
    }
}
