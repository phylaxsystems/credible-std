// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {LighterOutflowCircuitBreaker} from "../src/LighterOutflowCircuitBreaker.sol";

/// @notice Exposes the breaker's pure decision so the production policy is exercised directly. The
///         `watchCumulativeOutflow` trigger that fires the live assertion is driven by the executor's
///         rolling-window accounting and is not simulated by local `pcl test`, so the breach path is
///         validated through `_breakerTrips` rather than an armed `cl.assertion` call.
contract BreakerHarness is LighterOutflowCircuitBreaker {
    constructor(address bridge_, address collateral_, uint256 thresholdBps_, uint256 windowDuration_)
        LighterOutflowCircuitBreaker(bridge_, collateral_, thresholdBps_, windowDuration_)
    {}

    function trips(uint256 currentBps, uint256 thresholdBps, bool inDesertMode) external pure returns (bool) {
        return _breakerTrips(currentBps, thresholdBps, inDesertMode);
    }
}

contract LighterOutflowCircuitBreakerTest is Test {
    address internal constant BRIDGE = 0x3B4D794a66304F130a4Db8F2551B0070dfCf5ca7; // ZkLighter
    address internal constant COLLATERAL = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 internal constant THRESHOLD_BPS = 2000; // 20% of window-start TVL
    uint256 internal constant WINDOW = 1 hours;

    BreakerHarness internal breaker;

    function setUp() public {
        breaker = new BreakerHarness(BRIDGE, COLLATERAL, THRESHOLD_BPS, WINDOW);
    }

    // --- Decision logic ---------------------------------------------------

    function testTripsAtThresholdDuringNormalOperation() public view {
        assertTrue(breaker.trips(THRESHOLD_BPS, THRESHOLD_BPS, false));
    }

    function testTripsAboveThresholdDuringNormalOperation() public view {
        assertTrue(breaker.trips(THRESHOLD_BPS * 2, THRESHOLD_BPS, false));
    }

    function testStandsDownBelowThreshold() public view {
        assertFalse(breaker.trips(THRESHOLD_BPS - 1, THRESHOLD_BPS, false));
    }

    function testStandsDownInDesertModeEvenWhenBreached() public view {
        // Mass exits through the escape hatch must not be blocked, however large.
        assertFalse(breaker.trips(type(uint256).max, THRESHOLD_BPS, true));
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroBridge() public {
        vm.expectRevert(bytes("LighterBreaker: bridge zero"));
        new LighterOutflowCircuitBreaker(address(0), COLLATERAL, THRESHOLD_BPS, WINDOW);
    }

    function testRejectsZeroCollateral() public {
        vm.expectRevert(bytes("LighterBreaker: collateral zero"));
        new LighterOutflowCircuitBreaker(BRIDGE, address(0), THRESHOLD_BPS, WINDOW);
    }

    function testRejectsZeroThreshold() public {
        vm.expectRevert(bytes("LighterBreaker: threshold zero"));
        new LighterOutflowCircuitBreaker(BRIDGE, COLLATERAL, 0, WINDOW);
    }

    function testRejectsZeroWindow() public {
        vm.expectRevert(bytes("LighterBreaker: window zero"));
        new LighterOutflowCircuitBreaker(BRIDGE, COLLATERAL, THRESHOLD_BPS, 0);
    }
}
