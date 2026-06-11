// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {PhEvm} from "../../../src/PhEvm.sol";
import {FluidLiquidityFlowBreakerAssertion} from "../src/FluidLiquidityFlowBreakerAssertion.sol";
import {IFluidLiquidityLike} from "../src/FluidInterfaces.sol";

/// @notice Exposes the breaker's pure borrow-detection policy so it can be exercised directly.
/// @dev The `watchCumulativeOutflow` trigger that fires the live assertion is driven by the
///      executor's rolling-window accounting and is not simulated by local `pcl test`, so the
///      warning-tier policy is validated through `operateBorrowsToken` rather than an armed
///      `cl.assertion` call (mirroring the Lighter circuit-breaker example).
contract BreakerHarness is FluidLiquidityFlowBreakerAssertion {
    constructor(address[] memory tokens_) FluidLiquidityFlowBreakerAssertion(tokens_) {}

    function operateBorrowsToken(bytes memory input, address token) external pure returns (bool) {
        return _operateBorrowsToken(input, token);
    }

    function successfulOperateFilter() external pure returns (uint8 callType, bool successOnly) {
        PhEvm.CallFilter memory filter = _successfulOperateCalls();
        return (filter.callType, filter.successOnly);
    }
}

contract FluidLiquidityFlowBreakerAssertionTest is Test {
    address internal constant TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address internal constant OTHER = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    BreakerHarness internal breaker;

    function setUp() public {
        address[] memory tokens = new address[](1);
        tokens[0] = TOKEN;
        breaker = new BreakerHarness(tokens);
    }

    function _operateCalldata(address token, int256 supplyAmount, int256 borrowAmount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            IFluidLiquidityLike.operate.selector, token, supplyAmount, borrowAmount, address(0), address(0), bytes("")
        );
    }

    // --- Warning-tier policy: block new borrows of the breached token ----

    function testBorrowOfBreachedTokenIsBlocked() public view {
        assertTrue(breaker.operateBorrowsToken(_operateCalldata(TOKEN, int256(0), int256(100e6)), TOKEN));
    }

    function testRepayOfBreachedTokenIsAllowed() public view {
        assertFalse(breaker.operateBorrowsToken(_operateCalldata(TOKEN, int256(0), -int256(100e6)), TOKEN));
    }

    function testSupplyOnlyIsAllowed() public view {
        assertFalse(breaker.operateBorrowsToken(_operateCalldata(TOKEN, int256(100e6), int256(0)), TOKEN));
    }

    function testBorrowOfOtherTokenIsAllowed() public view {
        assertFalse(breaker.operateBorrowsToken(_operateCalldata(OTHER, int256(0), int256(100e6)), TOKEN));
    }

    function testWarningTierUsesSuccessfulCallFilter() public view {
        (uint8 callType, bool successOnly) = breaker.successfulOperateFilter();
        assertEq(callType, 1);
        assertTrue(successOnly);
    }

    // --- Deployment smoke -------------------------------------------------

    function testDeploys() public {
        address[] memory tokens = new address[](2);
        tokens[0] = TOKEN;
        tokens[1] = OTHER;
        FluidLiquidityFlowBreakerAssertion deployed = new FluidLiquidityFlowBreakerAssertion(tokens);
        assertEq(deployed.WARN_OUTFLOW_BPS(), 1_000);
        assertEq(deployed.CRITICAL_OUTFLOW_BPS(), 2_000);
    }

    function testRejectsNativeToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = NATIVE_TOKEN;

        vm.expectRevert(bytes("Fluid: native token breaker unsupported"));
        new FluidLiquidityFlowBreakerAssertion(tokens);
    }

    function testRejectsExternalCustodyToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = WEETH;

        vm.expectRevert(bytes("Fluid: external custody breaker unsupported"));
        new FluidLiquidityFlowBreakerAssertion(tokens);
    }
}
