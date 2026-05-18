// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IOracleRiskProtocol {
    function borrow(address asset, uint256 amount, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function repay(address asset, uint256 amount, address onBehalfOf) external;
    function oraclePrice(address asset) external view returns (uint256);
}

interface IMarketReferenceOracle {
    function marketPrice(address asset, address denomAsset) external view returns (uint256);
}

/// @notice When an oracle drifts from market, block risk-increasing calls and leave repay open.
/// @dev Protects against stale or synthetic oracle assumptions:
///      - borrowing against collateral that the protocol oracle overvalues relative to market;
///      - withdrawing collateral while the account's risk calculation uses a stale price;
///      - disabling repay/healing paths by registering too many selectors.
contract OracleReduceOnlyGateAssertion is Assertion {
    address public immutable WATCHED_ASSET;
    address public immutable DENOM_ASSET;
    address public immutable MARKET_REFERENCE;
    uint256 public immutable TOLERANCE_BPS;

    constructor(address watchedAsset_, address denomAsset_, address marketReference_, uint256 toleranceBps_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
        WATCHED_ASSET = watchedAsset_;
        DENOM_ASSET = denomAsset_;
        MARKET_REFERENCE = marketReference_;
        TOLERANCE_BPS = toleranceBps_;
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertOracleIsSaneForRiskIncrease.selector, IOracleRiskProtocol.borrow.selector);
        registerFnCallTrigger(this.assertOracleIsSaneForRiskIncrease.selector, IOracleRiskProtocol.withdraw.selector);
    }

    function assertOracleIsSaneForRiskIncrease() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        (address asset,,) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (address, uint256, address));
        if (asset != WATCHED_ASSET) return;

        // Compare the protocol's risk price with an independent market reference at the same pre-call point.
        address protocol = ph.getAssertionAdopter();
        uint256 reported = _readUintAt(
            protocol, abi.encodeCall(IOracleRiskProtocol.oraclePrice, (WATCHED_ASSET)), _preCall(ctx.callStart)
        );
        uint256 market = _readUintAt(
            MARKET_REFERENCE,
            abi.encodeCall(IMarketReferenceOracle.marketPrice, (WATCHED_ASSET, DENOM_ASSET)),
            _preCall(ctx.callStart)
        );
        require(market != 0, "missing market price");

        // Failure scenario: a risky borrow/withdraw path tries to proceed while the oracle is outside tolerance.
        require(_withinBps(reported, market, TOLERANCE_BPS), "oracle drift: reduce-only");
    }

    function _withinBps(uint256 a, uint256 b, uint256 toleranceBps) private pure returns (bool) {
        uint256 max = a > b ? a : b;
        uint256 min = a > b ? b : a;
        return (max - min) * 10_000 <= min * toleranceBps;
    }

    function _stripSelector(bytes memory input) private pure returns (bytes memory args) {
        require(input.length >= 4, "input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) args[i] = input[i + 4];
    }
}
