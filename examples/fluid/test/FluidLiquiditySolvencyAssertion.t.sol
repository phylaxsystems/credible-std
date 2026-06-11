// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {FluidLiquiditySolvencyAssertion} from "../src/FluidLiquiditySolvencyAssertion.sol";

/// @notice Minimal ERC20 whose `balanceOf` the assertion reads as the singleton's custody.
contract MockToken {
    mapping(address => uint256) public balanceOf;

    function setBalance(address account, uint256 amount) external {
        balanceOf[account] = amount;
    }
}

/// @notice Mock Fluid Liquidity Layer that stores packed accounting at the real mapping slots.
/// @dev Encodes interest-free supply/borrow as BigMath with exponent 0 (value << 8), leaving the
///      with-interest "raw" fields zero so the decode reduces to the plain amounts.
contract MockFluidLiquidity {
    uint256 internal constant SLOT_EXCHANGE_PRICES = 5;
    uint256 internal constant SLOT_TOTAL_AMOUNTS = 7;

    function setTotals(address token, uint256 totalSupply, uint256 totalBorrow) public {
        uint256 packed = ((totalSupply << 8) << 64) | ((totalBorrow << 8) << 192);
        bytes32 slot = keccak256(abi.encode(token, SLOT_TOTAL_AMOUNTS));
        assembly {
            sstore(slot, packed)
        }
    }

    function setExchangePrices(address token, uint256 supplyExchangePrice, uint256 borrowExchangePrice) public {
        uint256 packed = (supplyExchangePrice << 91) | (borrowExchangePrice << 155);
        bytes32 slot = keccak256(abi.encode(token, SLOT_EXCHANGE_PRICES));
        assembly {
            sstore(slot, packed)
        }
    }

    /// @notice Monitored mutation standing in for `operate`: rewrites the token's totals.
    function operate(address token, uint256 totalSupply, uint256 totalBorrow) external {
        setTotals(token, totalSupply, totalBorrow);
    }

    /// @notice Monitored mutation standing in for an interest update: rewrites exchange prices.
    function updatePrices(address token, uint256 supplyExchangePrice, uint256 borrowExchangePrice) external {
        setExchangePrices(token, supplyExchangePrice, borrowExchangePrice);
    }
}

contract FluidLiquiditySolvencyAssertionTest is Test, CredibleTest {
    MockFluidLiquidity internal liquidity;
    MockToken internal token;
    address[] internal tokens;

    uint256 internal constant SUPPLY = 1_000e6;
    uint256 internal constant BORROW = 400e6;
    uint256 internal constant HELD = 600e6; // = SUPPLY - BORROW, exactly solvent

    uint256 internal constant EP = 1e12; // initial exchange price

    function setUp() public {
        liquidity = new MockFluidLiquidity();
        token = new MockToken();

        token.setBalance(address(liquidity), HELD);
        liquidity.setTotals(address(token), SUPPLY, BORROW);
        liquidity.setExchangePrices(address(token), EP, EP);

        tokens.push(address(token));
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData =
            abi.encodePacked(type(FluidLiquiditySolvencyAssertion).creationCode, abi.encode(tokens));
        cl.assertion(address(liquidity), createData, fnSelector);
    }

    // --- Custody covers net supply ---------------------------------------

    function testCustodyHonestPasses() public {
        _arm(FluidLiquiditySolvencyAssertion.assertCustodyCoversNetSupply.selector);
        // Stays exactly solvent: held + borrow == supply.
        liquidity.operate(address(token), SUPPLY, BORROW);
    }

    function testCustodyInsolventTrips() public {
        _arm(FluidLiquiditySolvencyAssertion.assertCustodyCoversNetSupply.selector);
        // Supply inflated far beyond what custody + debt can back.
        vm.expectRevert(bytes("Fluid: liquidity custody below net supply"));
        liquidity.operate(address(token), 2_000e6, BORROW);
    }

    // --- Exchange price monotonicity -------------------------------------

    function testExchangePriceIncreasePasses() public {
        _arm(FluidLiquiditySolvencyAssertion.assertExchangePricesMonotonic.selector);
        // Interest accrual raises prices: allowed.
        liquidity.updatePrices(address(token), EP + 1, EP + 2);
    }

    function testExchangePriceDecreaseTrips() public {
        _arm(FluidLiquiditySolvencyAssertion.assertExchangePricesMonotonic.selector);
        // A drop in the stored supply exchange price signals corrupted accounting.
        vm.expectRevert(bytes("Fluid: supply exchange price decreased"));
        liquidity.updatePrices(address(token), EP - 1, EP);
    }
}
