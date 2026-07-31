// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

/// @title AaveV4HubFlowRateCircuitBreaker
/// @author Phylax Systems
/// @notice Shared policy for rate-limiting high-TVL assets held by an Aave v4 Hub.
/// @dev The assertion protects the Hub's external ERC20 custody rather than individual Spoke
///      selectors, so supplies, borrows, withdrawals, liquidations, sweeps, and future paths are
///      measured through the same balance signal.
///
///      Each configured asset has two independent hard limits in each direction:
///      - rolling 24-hour NET flow as bps of the Hub balance snapshotted at window start
///      - peak 10-second-bucket net-flow rate as bps of that snapshot per second
///
///      A 1 bps cumulative watcher is only the dispatch floor. Once dispatched, the assertion
///      rejects a transaction when EITHER the calibrated 24-hour limit or the calibrated peak-rate
///      limit is breached. The rate signal never suppresses a cumulative-flow breach.
abstract contract AaveV4HubFlowRateCircuitBreaker is Assertion {
    struct FlowLimits {
        uint256 inflowWindowBps;
        uint256 outflowWindowBps;
        uint256 inflowPeakRateBps;
        uint256 outflowPeakRateBps;
    }

    uint256 public constant FLOW_WINDOW = 24 hours;
    uint256 public constant DISPATCH_THRESHOLD_BPS = 1;

    address public immutable HUB;

    constructor(address hub_) {
        require(hub_ != address(0), "AaveV4Flow: zero hub");
        HUB = hub_;

        // inflowRate() and outflowRate() are currently experimental PhEVM precompiles.
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    /// @notice Hard-stops excessive rolling inflow or inflow acceleration into the configured Hub.
    /// @dev Invoked after the low dispatch floor is crossed. A failure means the transaction pushed
    ///      either 24-hour net inflow or the peak per-second inflow rate above its calibrated limit.
    function assertInflowWithinRateLimits() external view {
        require(ph.getAssertionAdopter() == HUB, "AaveV4Flow: configured hub is not adopter");

        PhEvm.InflowContext memory flow = ph.inflowContext();
        PhEvm.FlowRateContext memory rate = ph.inflowRate();
        require(flow.token != address(0) && rate.token == flow.token, "AaveV4Flow: bad inflow context");

        FlowLimits memory limits = _flowLimits(flow.token);
        require(flow.currentBps <= limits.inflowWindowBps, "AaveV4Flow: 24h inflow limit");
        require(rate.peakRateBps <= limits.inflowPeakRateBps, "AaveV4Flow: inflow rate limit");
    }

    /// @notice Hard-stops excessive rolling outflow or outflow acceleration from the configured Hub.
    /// @dev Invoked after the low dispatch floor is crossed. A failure means the transaction pushed
    ///      either 24-hour net outflow or the peak per-second outflow rate above its calibrated limit.
    function assertOutflowWithinRateLimits() external view {
        require(ph.getAssertionAdopter() == HUB, "AaveV4Flow: configured hub is not adopter");

        PhEvm.OutflowContext memory flow = ph.outflowContext();
        PhEvm.FlowRateContext memory rate = ph.outflowRate();
        require(flow.token != address(0) && rate.token == flow.token, "AaveV4Flow: bad outflow context");

        FlowLimits memory limits = _flowLimits(flow.token);
        require(flow.currentBps <= limits.outflowWindowBps, "AaveV4Flow: 24h outflow limit");
        require(rate.peakRateBps <= limits.outflowPeakRateBps, "AaveV4Flow: outflow rate limit");
    }

    function _watchAsset(address token) internal view {
        watchCumulativeInflow(token, DISPATCH_THRESHOLD_BPS, FLOW_WINDOW, this.assertInflowWithinRateLimits.selector);
        watchCumulativeOutflow(token, DISPATCH_THRESHOLD_BPS, FLOW_WINDOW, this.assertOutflowWithinRateLimits.selector);
    }

    function _inflowTrips(address token, uint256 currentBps, uint256 peakRateBps) internal pure returns (bool) {
        FlowLimits memory limits = _flowLimits(token);
        return currentBps > limits.inflowWindowBps || peakRateBps > limits.inflowPeakRateBps;
    }

    function _outflowTrips(address token, uint256 currentBps, uint256 peakRateBps) internal pure returns (bool) {
        FlowLimits memory limits = _flowLimits(token);
        return currentBps > limits.outflowWindowBps || peakRateBps > limits.outflowPeakRateBps;
    }

    function _flowLimits(address token) internal pure virtual returns (FlowLimits memory);
}

/// @title AaveV4EthereumCoreHubFlowRateCircuitBreaker
/// @author Phylax Systems
/// @notice Ready-to-adopt Core Hub breaker for Aave v4's three highest-TVL Ethereum assets.
/// @dev Asset ranking comes from DefiLlama's aggregate Aave v4 token TVL on 2026-07-30:
///      WBTC ($52.35m), USDG ($30.84m), and wstETH ($29.40m). Limits are 120% of each
///      Core Hub asset's maximum observed rolling 24-hour net flow and 10-second peak flow rate
///      during Ethereum blocks 25,430,974 through 25,646,159.
contract AaveV4EthereumCoreHubFlowRateCircuitBreaker is AaveV4HubFlowRateCircuitBreaker {
    address public constant CORE_HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    constructor() AaveV4HubFlowRateCircuitBreaker(CORE_HUB) {}

    function triggers() external view virtual override {
        _watchAsset(WBTC);
        _watchAsset(USDG);
        _watchAsset(WSTETH);
    }

    function _flowLimits(address token) internal pure override returns (FlowLimits memory limits) {
        if (token == WBTC) {
            return
                FlowLimits({
                    inflowWindowBps: 1_184, outflowWindowBps: 110, inflowPeakRateBps: 48, outflowPeakRateBps: 9
                });
        }
        if (token == USDG) {
            return FlowLimits({
                inflowWindowBps: 5_196, outflowWindowBps: 6_438, inflowPeakRateBps: 527, outflowPeakRateBps: 154
            });
        }
        if (token == WSTETH) {
            return
                FlowLimits({
                    inflowWindowBps: 1_906, outflowWindowBps: 932, inflowPeakRateBps: 58, outflowPeakRateBps: 94
                });
        }
        revert("AaveV4Flow: unsupported Core asset");
    }
}

/// @title AaveV4EthereumPrimeHubFlowRateCircuitBreaker
/// @author Phylax Systems
/// @notice Companion breaker for top-three assets whose custody is also split into the Prime Hub.
/// @dev WBTC and wstETH are present in both Core and Prime. A flow watcher measures only its
///      assertion adopter, so this companion assertion must be adopted by Prime to avoid leaving
///      that portion of the two assets unprotected. USDG is held only by Core.
contract AaveV4EthereumPrimeHubFlowRateCircuitBreaker is AaveV4HubFlowRateCircuitBreaker {
    address public constant PRIME_HUB = 0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    constructor() AaveV4HubFlowRateCircuitBreaker(PRIME_HUB) {}

    function triggers() external view virtual override {
        _watchAsset(WBTC);
        _watchAsset(WSTETH);
    }

    function _flowLimits(address token) internal pure override returns (FlowLimits memory limits) {
        if (token == WBTC) {
            return FlowLimits({
                inflowWindowBps: 2_102, outflowWindowBps: 2_367, inflowPeakRateBps: 149, outflowPeakRateBps: 178
            });
        }
        if (token == WSTETH) {
            return
                FlowLimits({
                    inflowWindowBps: 3_485, outflowWindowBps: 909, inflowPeakRateBps: 211, outflowPeakRateBps: 73
                });
        }
        revert("AaveV4Flow: unsupported Prime asset");
    }
}
