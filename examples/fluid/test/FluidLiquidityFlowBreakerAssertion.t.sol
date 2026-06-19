// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {PhEvm} from "../../../src/PhEvm.sol";
import {FluidLiquidityFlowBreakerAssertion} from "../src/FluidLiquidityFlowBreakerAssertion.sol";
import {IFluidLiquidityLike} from "../src/FluidInterfaces.sol";

/// @notice Exposes the breaker's pure borrow-detection policy so it can be exercised directly.
/// @dev The `watchCumulativeOutflow` trigger that fires the live assertion, and the `ph.matchingCalls`
///      query it feeds on, are driven by the executor's rolling-window accounting and are not
///      simulated by local `pcl test`, so the warning-tier policy is validated through
///      `operateBorrowsToken` rather than an armed `cl.assertion` call (mirroring the Lighter
///      circuit-breaker example). Critically, the policy is exercised against the exact
///      selector-stripped argument tail that `ph.matchingCalls(...).input` returns in production — see
///      `_matchingCallsInput` — so the selector-offset regression this fix addresses is caught here.
contract BreakerHarness is FluidLiquidityFlowBreakerAssertion {
    constructor(address[] memory tokens_) FluidLiquidityFlowBreakerAssertion(tokens_) {}

    function operateBorrowsToken(bytes memory input, address token) external pure returns (bool) {
        return _operateBorrowsToken(input, token);
    }

    function successfulOperateFilter()
        external
        pure
        returns (uint8 callType, uint32 minDepth, uint32 maxDepth, bool topLevelOnly, bool successOnly)
    {
        PhEvm.CallFilter memory filter = _successfulOperateCalls();
        return (filter.callType, filter.minDepth, filter.maxDepth, filter.topLevelOnly, filter.successOnly);
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

    /// @notice Builds the input the breaker actually decodes in production.
    /// @dev `ph.matchingCalls(...).input` returns the ABI argument tail with the 4-byte selector (the
    ///      query key) stripped, so the policy must be tested against that shape, NOT against full
    ///      selector-prefixed calldata. `abi.encode(args)` is byte-identical to
    ///      `abi.encodeWithSelector(sel, args)[4:]` (asserted by
    ///      `testMatchingCallsInputIsSelectorStripped`). Feeding selector-prefixed calldata here is
    ///      what masked the original decode bug.
    function _matchingCallsInput(address token, int256 supplyAmount, int256 borrowAmount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(token, supplyAmount, borrowAmount, address(0), address(0), bytes(""));
    }

    // --- Warning-tier policy: block new borrows of the breached token ----

    function testBorrowOfBreachedTokenIsBlocked() public view {
        assertTrue(breaker.operateBorrowsToken(_matchingCallsInput(TOKEN, int256(0), int256(100e6)), TOKEN));
    }

    function testRepayOfBreachedTokenIsAllowed() public view {
        assertFalse(breaker.operateBorrowsToken(_matchingCallsInput(TOKEN, int256(0), -int256(100e6)), TOKEN));
    }

    function testSupplyOnlyIsAllowed() public view {
        assertFalse(breaker.operateBorrowsToken(_matchingCallsInput(TOKEN, int256(100e6), int256(0)), TOKEN));
    }

    function testBorrowOfOtherTokenIsAllowed() public view {
        assertFalse(breaker.operateBorrowsToken(_matchingCallsInput(OTHER, int256(0), int256(100e6)), TOKEN));
    }

    // --- Regression guards for the selector-stripped input contract ------

    /// @dev Pins the production input shape: the args-only encoding the policy decodes must equal the
    ///      selector-prefixed operate calldata with its leading 4 bytes removed — exactly what
    ///      `ph.matchingCalls(...).input` yields. Breaks if `_matchingCallsInput` drifts from reality.
    function testMatchingCallsInputIsSelectorStripped() public pure {
        bytes memory full = abi.encodeWithSelector(
            IFluidLiquidityLike.operate.selector, TOKEN, int256(0), int256(100e6), address(0), address(0), bytes("")
        );
        bytes memory stripped = new bytes(full.length - 4);
        for (uint256 i; i < stripped.length; ++i) {
            stripped[i] = full[i + 4];
        }
        assertEq(keccak256(stripped), keccak256(_matchingCallsInput(TOKEN, int256(0), int256(100e6))));
    }

    /// @dev If the 4-byte selector offset is ever re-added to the arg decoders, full selector-prefixed
    ///      calldata would decode as a borrow of TOKEN and this would flip to a (spurious) detection.
    ///      With the correct args-only decode the selector shifts the token word, so no match.
    function testSelectorPrefixedCalldataIsNotDecodedAsBorrow() public view {
        bytes memory full = abi.encodeWithSelector(
            IFluidLiquidityLike.operate.selector, TOKEN, int256(0), int256(100e6), address(0), address(0), bytes("")
        );
        assertFalse(breaker.operateBorrowsToken(full, TOKEN));
    }

    function testWarningTierUsesSuccessfulCallFilter() public view {
        (uint8 callType, uint32 minDepth, uint32 maxDepth, bool topLevelOnly, bool successOnly) =
            breaker.successfulOperateFilter();
        assertEq(callType, 1); // CALL only
        assertTrue(successOnly);
        // Scan `operate` at ANY depth so router/proxy-routed borrows of the breached token are not
        // missed — depth must not be left to precompile defaults.
        assertEq(minDepth, 0);
        assertEq(maxDepth, type(uint32).max);
        assertFalse(topLevelOnly);
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
