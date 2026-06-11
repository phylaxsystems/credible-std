// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {FluidFTokenSharePriceAssertion} from "../src/FluidFTokenSharePriceAssertion.sol";

/// @notice Mock fToken exposing ERC-4626 `totalAssets`/`totalSupply` getters.
contract MockFToken {
    uint256 public totalAssets;
    uint256 public totalSupply;

    function setState(uint256 assets_, uint256 supply_) public {
        totalAssets = assets_;
        totalSupply = supply_;
    }

    /// @notice Monitored mutation standing in for a deposit/withdraw/yield update.
    function operate(uint256 assets_, uint256 supply_) external {
        setState(assets_, supply_);
    }
}

contract FluidFTokenSharePriceAssertionTest is Test, CredibleTest {
    MockFToken internal fToken;

    function setUp() public {
        fToken = new MockFToken();
        // Start at share price 1.0 with a non-trivial supply.
        fToken.setState(1_000e18, 1_000e18);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(type(FluidFTokenSharePriceAssertion).creationCode);
        cl.assertion(address(fToken), createData, FluidFTokenSharePriceAssertion.assertSharePriceNonDecreasing.selector);
    }

    function testYieldAccrualPasses() public {
        _arm();
        // Assets grow faster than supply: share price rises (yield).
        fToken.operate(1_100e18, 1_050e18);
    }

    function testProportionalDepositPasses() public {
        _arm();
        // Principal flow scales both sides: share price flat.
        fToken.operate(2_000e18, 2_000e18);
    }

    function testSharePriceDropTrips() public {
        _arm();
        // Assets fall while supply holds: each share is worth less.
        vm.expectRevert(bytes("Fluid: fToken share price decreased"));
        fToken.operate(900e18, 1_000e18);
    }
}
