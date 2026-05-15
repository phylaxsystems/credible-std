// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Assertion} from "../../../src/Assertion.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {IERC4626} from "../../../src/protection/vault/IERC4626.sol";

address constant SPEC_RECORDER = address(uint160(uint256(keccak256("SpecRecorder"))));

interface IVaultDemoDonate {
    function donateAssets(uint256 assets) external;
}

interface ICuratorVaultDemo {
    function allocate(address market, uint256 assets) external;
}

interface IMarketHealthDemo {
    function utilizationBps() external view returns (uint256);
    function oracle() external view returns (address);
}

interface IPriceOracleDemo {
    function price() external view returns (uint256);
}

/// @notice Concrete demo wrapper for the reusable ERC4626 assetsMatchSharePrice protection.
contract VaultAssetsMatchSharePriceAssertion is Assertion {
    address internal immutable vault;
    uint256 internal immutable toleranceBps;

    constructor(address vault_, uint256 toleranceBps_) {
        vault = vault_;
        toleranceBps = toleranceBps_;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertSharePriceEnvelope.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.deposit.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.mint.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.withdraw.selector);
        registerFnCallTrigger(this.assertPerCallSharePrice.selector, IERC4626.redeem.selector);
    }

    function assertSharePriceEnvelope() external {
        require(ph.assetsMatchSharePrice(vault, toleranceBps), "VaultDemo: share price drift");
    }

    function assertPerCallSharePrice() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        require(
            ph.assetsMatchSharePriceAt(vault, toleranceBps, _preCall(ctx.callStart), _postCall(ctx.callEnd)),
            "VaultDemo: call-level share price drift"
        );
    }
}

/// @notice Treats `convertToAssets(probeShares)` as an oracle and checks it for intra-tx deviation.
contract VaultConvertToAssetsOracleSanityAssertion is Assertion {
    address internal immutable vault;
    uint256 internal immutable probeShares;
    uint256 internal immutable maxDeviationBps;

    constructor(address vault_, uint256 probeShares_, uint256 maxDeviationBps_) {
        vault = vault_;
        probeShares = probeShares_;
        maxDeviationBps = maxDeviationBps_;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertConvertToAssetsOracleSanity.selector, IVaultDemoDonate.donateAssets.selector);
    }

    function assertConvertToAssetsOracleSanity() external {
        require(
            ph.oracleSanity(vault, abi.encodeCall(IERC4626.convertToAssets, (probeShares)), maxDeviationBps),
            "VaultDemo: convertToAssets deviated"
        );
    }
}

/// @notice Blocks curator allocations when the target market is already degraded or its oracle moved intra-tx.
contract CuratorMarketHealthAssertion is Assertion {
    address internal immutable curatorVault;
    uint256 internal immutable maxUtilizationBps;
    uint256 internal immutable maxOracleDeviationBps;

    constructor(address curatorVault_, uint256 maxUtilizationBps_, uint256 maxOracleDeviationBps_) {
        curatorVault = curatorVault_;
        maxUtilizationBps = maxUtilizationBps_;
        maxOracleDeviationBps = maxOracleDeviationBps_;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertTargetMarketHealthy.selector, ICuratorVaultDemo.allocate.selector);
    }

    function assertTargetMarketHealthy() external {
        require(ph.getAssertionAdopter() == curatorVault, "VaultDemo: wrong curator vault");

        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        (address market,) = abi.decode(_stripSelector(input), (address, uint256));

        uint256 utilization =
            _readUintAt(market, abi.encodeCall(IMarketHealthDemo.utilizationBps, ()), _preCall(ctx.callStart));
        require(utilization <= maxUtilizationBps, "VaultDemo: market utilization unhealthy");

        address marketOracle =
            _readAddressAt(market, abi.encodeCall(IMarketHealthDemo.oracle, ()), _preCall(ctx.callStart));
        require(
            ph.oracleSanity(marketOracle, abi.encodeCall(IPriceOracleDemo.price, ()), maxOracleDeviationBps),
            "VaultDemo: market oracle deviated"
        );
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "VaultDemo: input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}

/// @notice Adds a circuit breaker that trips when depositing more than 25% in 6 hours or withdrawing 25% in 24 hours
contract VaultCircuitBreakerAssertion is Assertion {
    uint256 internal constant THRESHOLD_BPS = 2_500;
    uint256 internal constant INFLOW_WINDOW = 6 hours;
    uint256 internal constant OUTFLOW_WINDOW = 24 hours;

    address public immutable vault;
    address public immutable asset;

    constructor(address vault_, address asset_) {
        vault = vault_;
        asset = asset_;
        _registerReshiramSpec();
    }

    function triggers() external view override {
        watchCumulativeInflow(asset, THRESHOLD_BPS, INFLOW_WINDOW, this.assertCumulativeInflow.selector);
        watchCumulativeOutflow(asset, THRESHOLD_BPS, OUTFLOW_WINDOW, this.assertCumulativeOutflow.selector);
    }

    function assertCumulativeInflow() external view {
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ph.getAssertionAdopter() == vault, "VaultDemo: wrong vault");
        require(ctx.token == asset, "VaultDemo: wrong inflow token");

        revert("VaultDemo: cumulative inflow breaker tripped");
    }

    function assertCumulativeOutflow() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ph.getAssertionAdopter() == vault, "VaultDemo: wrong vault");
        require(ctx.token == asset, "VaultDemo: wrong outflow token");

        revert("VaultDemo: cumulative outflow breaker tripped");
    }
}

function _registerReshiramSpec() {
    (bool ok,) = SPEC_RECORDER.call(
        abi.encodeWithSelector(bytes4(keccak256("registerAssertionSpec(uint8)")), AssertionSpec.Reshiram)
    );
    require(ok, "VaultDemo: spec registration failed");
}
