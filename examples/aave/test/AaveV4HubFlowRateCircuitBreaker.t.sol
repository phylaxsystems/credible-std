// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    AaveV4HubFlowRateCircuitBreaker,
    AaveV4EthereumCoreHubFlowRateCircuitBreaker,
    AaveV4EthereumPrimeHubFlowRateCircuitBreaker
} from "../src/AaveV4HubFlowRateCircuitBreaker.sol";

/// @notice Exposes the production Core Hub breaker's pure OR-policy for local behavior tests.
/// @dev Rolling flow and rate contexts are executor-maintained and are not synthesized by local
///      `pcl test`, so these tests exercise the exact internal decision used by the live assertion.
contract CoreFlowRateBreakerHarness is AaveV4EthereumCoreHubFlowRateCircuitBreaker {
    function inflowTrips(address token, uint256 currentBps, uint256 peakRateBps) external pure returns (bool) {
        return _inflowTrips(token, currentBps, peakRateBps);
    }

    function outflowTrips(address token, uint256 currentBps, uint256 peakRateBps) external pure returns (bool) {
        return _outflowTrips(token, currentBps, peakRateBps);
    }
}

/// @notice Exposes the production Prime Hub breaker's pure OR-policy for local behavior tests.
contract PrimeFlowRateBreakerHarness is AaveV4EthereumPrimeHubFlowRateCircuitBreaker {
    function inflowTrips(address token, uint256 currentBps, uint256 peakRateBps) external pure returns (bool) {
        return _inflowTrips(token, currentBps, peakRateBps);
    }

    function outflowTrips(address token, uint256 currentBps, uint256 peakRateBps) external pure returns (bool) {
        return _outflowTrips(token, currentBps, peakRateBps);
    }
}

/// @notice Call-triggered fixture for real PCL dispatch of the production OR-policy.
/// @dev Local PCL does not synthesize rolling flow contexts, so constructor values stand in for
///      `currentBps` and `peakRateBps`; the fixture still dispatches through `cl.assertion` and
///      executes the same `_inflowTrips` / `_outflowTrips` helpers used by production.
contract ArmedFlowRateBreaker is AaveV4HubFlowRateCircuitBreaker {
    address internal constant TEST_TOKEN = address(0xBEEF);
    uint256 internal constant TEST_WINDOW_LIMIT_BPS = 100;
    uint256 internal constant TEST_PEAK_LIMIT_BPS = 10;

    bool internal immutable testInflow;
    uint256 internal immutable testCurrentBps;
    uint256 internal immutable testPeakRateBps;

    constructor(address hub_, bool inflow_, uint256 currentBps_, uint256 peakRateBps_)
        AaveV4HubFlowRateCircuitBreaker(hub_)
    {
        testInflow = inflow_;
        testCurrentBps = currentBps_;
        testPeakRateBps = peakRateBps_;
    }

    function triggers() external view override {
        registerCallTrigger(this.assertTestPolicy.selector);
    }

    function assertTestPolicy() external view {
        require(ph.getAssertionAdopter() == HUB, "AaveV4Flow: configured hub is not adopter");
        if (testInflow) {
            require(!_inflowTrips(TEST_TOKEN, testCurrentBps, testPeakRateBps), "AaveV4Flow: test inflow breaker");
        } else {
            require(!_outflowTrips(TEST_TOKEN, testCurrentBps, testPeakRateBps), "AaveV4Flow: test outflow breaker");
        }
    }

    function _flowLimits(address token) internal pure override returns (FlowLimits memory limits) {
        require(token == TEST_TOKEN, "AaveV4Flow: unsupported test asset");
        return FlowLimits({
            inflowWindowBps: TEST_WINDOW_LIMIT_BPS,
            outflowWindowBps: TEST_WINDOW_LIMIT_BPS,
            inflowPeakRateBps: TEST_PEAK_LIMIT_BPS,
            outflowPeakRateBps: TEST_PEAK_LIMIT_BPS
        });
    }
}

contract MockAaveV4HubTarget {
    uint256 public pokes;

    function poke() external {
        pokes++;
    }
}

contract AaveV4HubFlowRateCircuitBreakerTest is Test, CredibleTest {
    CoreFlowRateBreakerHarness internal core;
    PrimeFlowRateBreakerHarness internal prime;
    MockAaveV4HubTarget internal adopter;

    function setUp() public {
        core = new CoreFlowRateBreakerHarness();
        prime = new PrimeFlowRateBreakerHarness();
        adopter = new MockAaveV4HubTarget();
    }

    function _arm(bool inflow, uint256 currentBps, uint256 peakRateBps) internal {
        bytes memory createData = abi.encodePacked(
            type(ArmedFlowRateBreaker).creationCode, abi.encode(address(adopter), inflow, currentBps, peakRateBps)
        );
        cl.assertion(address(adopter), createData, ArmedFlowRateBreaker.assertTestPolicy.selector);
    }

    // --- production threshold tables -------------------------------------

    function testCoreWbtcAllowsExactInflowLimits() public view {
        assertFalse(core.inflowTrips(core.WBTC(), 5_000, 7_500));
    }

    function testCoreWbtcTripsOnWindowInflow() public view {
        assertTrue(core.inflowTrips(core.WBTC(), 5_001, 7_500));
    }

    function testCoreWbtcTripsOnPeakInflowRate() public view {
        assertTrue(core.inflowTrips(core.WBTC(), 5_000, 7_501));
    }

    function testCoreUsdgTripsOnWindowOutflow() public view {
        assertTrue(core.outflowTrips(core.USDG(), 5_001, 7_500));
    }

    function testCoreWstethTripsOnPeakOutflowRate() public view {
        assertTrue(core.outflowTrips(core.WSTETH(), 5_000, 7_501));
    }

    function testPrimeWbtcAllowsExactOutflowLimits() public view {
        assertFalse(prime.outflowTrips(prime.WBTC(), 5_000, 7_500));
    }

    function testPrimeWstethTripsOnWindowInflow() public view {
        assertTrue(prime.inflowTrips(prime.WSTETH(), 5_001, 7_500));
    }

    function testCoreRejectsUnsupportedAsset() public {
        vm.expectRevert(bytes("AaveV4Flow: unsupported Core asset"));
        core.inflowTrips(makeAddr("unsupported"), 0, 0);
    }

    function testPrimeRejectsUnsupportedAsset() public {
        vm.expectRevert(bytes("AaveV4Flow: unsupported Prime asset"));
        prime.outflowTrips(makeAddr("unsupported"), 0, 0);
    }

    function testDeploymentConstants() public view {
        assertEq(core.HUB(), core.CORE_HUB());
        assertEq(prime.HUB(), prime.PRIME_HUB());
        assertEq(core.FLOW_WINDOW(), 24 hours);
        assertEq(core.DISPATCH_THRESHOLD_BPS(), 1);
    }

    // --- dispatched breaker policy ---------------------------------------

    function testDispatchedPolicyAllowsExactLimits() public {
        _arm(true, 100, 10);
        adopter.poke();
        assertEq(adopter.pokes(), 1);
    }

    function testDispatchedPolicyTripsOnWindowLimit() public {
        _arm(false, 101, 10);
        vm.expectRevert(bytes("AaveV4Flow: test outflow breaker"));
        adopter.poke();
    }

    function testDispatchedPolicyTripsOnPeakRateLimit() public {
        _arm(true, 100, 11);
        vm.expectRevert(bytes("AaveV4Flow: test inflow breaker"));
        adopter.poke();
    }
}
