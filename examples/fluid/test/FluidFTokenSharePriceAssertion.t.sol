// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {FluidFTokenSharePriceAssertion} from "../src/FluidFTokenSharePriceAssertion.sol";

/// @notice Mock fToken exposing ERC-4626 `totalAssets`/`totalSupply` getters.
contract MockFToken {
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    uint256 public exchangePrice;
    uint256 public totalAssets;
    uint256 public totalSupply;

    function setState(uint256 exchangePrice_, uint256 supply_) public {
        exchangePrice = exchangePrice_;
        totalSupply = supply_;
        totalAssets = (exchangePrice_ * supply_) / EXCHANGE_PRICES_PRECISION;
    }

    /// @notice Monitored mutation standing in for a deposit/withdraw/yield update.
    function operate(uint256 exchangePrice_, uint256 supply_) external {
        setState(exchangePrice_, supply_);
    }

    function convertToAssets(uint256 shares_) external view returns (uint256) {
        return (shares_ * exchangePrice) / EXCHANGE_PRICES_PRECISION;
    }
}

contract FluidFTokenSharePriceAssertionTest is Test, CredibleTest {
    MockFToken internal fToken;

    function setUp() public {
        fToken = new MockFToken();
        // Start at share price 1.0 with a non-trivial supply.
        fToken.setState(1e12, 1_000e18);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(type(FluidFTokenSharePriceAssertion).creationCode);
        cl.assertion(address(fToken), createData, FluidFTokenSharePriceAssertion.assertSharePriceNonDecreasing.selector);
    }

    function testYieldAccrualPasses() public {
        _arm();
        // Exchange price rises with yield.
        fToken.operate(1_100_000_000_000, 1_050e18);
    }

    function testProportionalDepositPasses() public {
        _arm();
        // Principal flow changes supply while share price stays flat.
        fToken.operate(1e12, 2_000e18);
    }

    function testSupplyChangeRoundingPassesAtFlatExchangePrice() public {
        fToken.setState(1_000_000_000_001, 999e18);

        _arm();
        // Fixed-share sampling is independent of totalAssets floor rounding from a supply change.
        fToken.operate(1_000_000_000_001, 2_001e18);
    }

    function testSharePriceDropTrips() public {
        _arm();
        // Exchange price falls: each share is worth less.
        vm.expectRevert(bytes("Fluid: fToken share price decreased"));
        fToken.operate(900_000_000_000, 1_000e18);
    }
}
