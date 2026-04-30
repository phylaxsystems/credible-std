// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";

import {AaveV3FlatAssertion} from "../../fixtures/lending/AaveV3FlatAssertion.sol";
import {MockAaveV3Pool} from "../../fixtures/lending/MockAaveV3Pool.sol";

/// @title AaveV3OperationSafetyBehaviorTest
/// @notice cl.assertion-armed tests for an Aave v3-like post-borrow solvency assertion.
/// @dev Uses a flat self-contained assertion (`AaveV3FlatAssertion`) instead of the production
///      suite-pattern assertion. The Credible Layer's assertion-deploy runtime does not preserve
///      child contracts that an assertion `new`s in its constructor — only the adopter (pool) is
///      visible at execution time, so the suite-as-separate-contract pattern cannot be exercised
///      end-to-end here.
///
///      The mock pool exposes `getUserAccountData(account)` and a `nextHealthFactor` knob the
///      test pre-configures so the post-call snapshot reflects whatever solvency outcome the
///      test wants to assert on.
contract AaveV3OperationSafetyBehaviorTest is Test, CredibleTest {
    address internal addressesProvider = makeAddr("addressesProvider");
    address internal asset = makeAddr("asset");
    address internal alice = makeAddr("alice");

    MockAaveV3Pool internal pool;

    uint256 internal constant HEALTHY_HF = 2e18;
    uint256 internal constant UNHEALTHY_HF = 9e17;

    function setUp() public {
        pool = new MockAaveV3Pool(addressesProvider);
        pool.setAccount({
            user: alice,
            totalCollateralBase: 200e18,
            totalDebtBase: 100e18,
            availableBorrowsBase: 50e18,
            currentLiquidationThreshold: 8000,
            ltv: 7000,
            healthFactor: HEALTHY_HF
        });
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(type(AaveV3FlatAssertion).creationCode, abi.encode(address(pool)));
        cl.assertion(address(pool), createData, AaveV3FlatAssertion.assertBorrowSolvency.selector);
    }

    /// @notice A borrow that leaves the borrower's health factor above 1.0 must pass solvency.
    function testHealthyBorrowPasses() public {
        pool.setNextHealthFactor(alice, 1.5e18);

        _arm();
        vm.prank(alice);
        pool.borrow(asset, 10e18, 2, 0, alice);
    }

    /// @notice A borrow that pushes the borrower's health factor below 1.0 must trip the
    ///         post-operation solvency check.
    function testUnsolventBorrowTripsSolvencyCheck() public {
        pool.setNextHealthFactor(alice, UNHEALTHY_HF);

        _arm();
        vm.prank(alice);
        vm.expectRevert();
        pool.borrow(asset, 10e18, 2, 0, alice);
    }

    /// @notice The flat assertion deploys cleanly outside the pcl runtime.
    function testFlatAssertionDeploys() public {
        AaveV3FlatAssertion assertion = new AaveV3FlatAssertion(address(pool));
        assertTrue(address(assertion) != address(0));
    }
}
