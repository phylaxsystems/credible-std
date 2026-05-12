// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";
import {
    ICapGateFractionalReserveLike,
    ICapGateVaultLike,
    IERC20BalanceReaderLike
} from "./CapRedemptionGateInterfaces.sol";

/// @title CapRedemptionGateAssertion
/// @author Phylax Systems
/// @notice Example Cap vault bank-run gate using rolling per-asset outflow thresholds.
/// @dev Deploy this assertion against the Cap cUSD Vault and pass the supported underlying
///      assets. Each asset gets its own independent watcher so a run on one reserve does not
///      block unrelated reserves. The gate uses the built-in cumulative outflow trigger, then
///      recalculates utilization against Cap's true per-asset TVL: idle vault balance plus the
///      amount loaned into fractional-reserve strategies.
///
///      Selector policy:
///      - >= 15% absolute outflow over 72h blocks new `borrow(asset,amount,receiver)`.
///      - >= 30% absolute outflow over 72h blocks user `burn` and `redeem` redemptions.
///      - >= 50% absolute outflow over 72h blocks `investAll(asset)`.
///      - `mint`, `repay`, `divestAll`, and rescue/admin paths are intentionally not gated.
contract CapRedemptionGateAssertion is Assertion {
    uint256 internal constant WINDOW = 72 hours;
    uint256 internal constant TIER2_BPS = 1_500;
    uint256 internal constant TIER3_BPS = 3_000;
    uint256 internal constant TIER3_HALT_INVEST_BPS = 5_000;

    // Use a low trigger threshold because the built-in TVL snapshot is the idle vault balance.
    // The assertion recalculates against strategy-inclusive TVL before deciding what to block.
    uint256 internal constant WATCH_TRIGGER_BPS = 1;
    uint256 internal constant MAX_MATCHING_CALLS = 1024;

    address internal immutable ASSET0;
    address internal immutable ASSET1;
    address internal immutable ASSET2;
    address internal immutable ASSET3;
    address internal immutable ASSET4;

    constructor(address _asset0, address _asset1, address _asset2, address _asset3, address _asset4) {
        ASSET0 = _asset0;
        ASSET1 = _asset1;
        ASSET2 = _asset2;
        ASSET3 = _asset3;
        ASSET4 = _asset4;

        registerAssertionSpec(AssertionSpec.Experimental);
    }

    function triggers() external view override {
        _watchAsset(ASSET0);
        _watchAsset(ASSET1);
        _watchAsset(ASSET2);
        _watchAsset(ASSET3);
        _watchAsset(ASSET4);
    }

    /// @notice Applies Cap's tiered per-asset withdrawal gate after a rolling outflow breach.
    /// @dev Reads `ph.outflowContext()` for the token that breached the built-in watcher, then
    ///      recomputes outflow bps using `absoluteOutflow / (idle + loaned)` at the PreTx fork.
    ///      Fails only when the current transaction contains a selector blocked at the active
    ///      tier for the same asset.
    function assertCapRedemptionGate() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(_isWatchedAsset(ctx.token), "CapGate: unwatched asset");

        uint256 currentBps = _absoluteOutflowBps(ctx);
        if (currentBps < TIER2_BPS) return;

        if (_hasAssetCall(ICapGateVaultLike.borrow.selector, ctx.token)) {
            revert("CapGate: borrow disabled");
        }

        if (currentBps >= TIER3_BPS) {
            if (_hasAssetCall(ICapGateVaultLike.burn.selector, ctx.token) || _hasRedeemCall()) {
                revert("CapGate: redemption capacity reached");
            }
        }

        if (currentBps >= TIER3_HALT_INVEST_BPS) {
            if (_hasAssetCall(ICapGateFractionalReserveLike.investAll.selector, ctx.token)) {
                revert("CapGate: invest disabled");
            }
        }
    }

    function _watchAsset(address asset) internal view {
        if (asset == address(0)) return;
        watchCumulativeOutflow(asset, WATCH_TRIGGER_BPS, WINDOW, this.assertCapRedemptionGate.selector);
    }

    function _absoluteOutflowBps(PhEvm.OutflowContext memory ctx) internal view returns (uint256) {
        uint256 trueTvl = _trueTvlAt(ctx.token, _preTx());
        require(trueTvl > 0, "CapGate: zero TVL");
        return ctx.absoluteOutflow * 10_000 / trueTvl;
    }

    function _trueTvlAt(address asset, PhEvm.ForkId memory fork) internal view returns (uint256) {
        address vault = ph.getAssertionAdopter();
        uint256 idle = _readUintAt(asset, abi.encodeCall(IERC20BalanceReaderLike.balanceOf, (vault)), fork);
        uint256 loaned = _readUintAt(vault, abi.encodeCall(ICapGateFractionalReserveLike.loaned, (asset)), fork);
        return idle + loaned;
    }

    function _hasAssetCall(bytes4 selector, address asset) internal view returns (bool) {
        PhEvm.TriggerCall[] memory calls =
            ph.matchingCalls(ph.getAssertionAdopter(), selector, _successOnlyFilter(), MAX_MATCHING_CALLS);

        for (uint256 i; i < calls.length; ++i) {
            bytes memory input = ph.callinputAt(calls[i].callId);
            if (_addressArg(input, 0) == asset) return true;
        }

        return false;
    }

    function _hasRedeemCall() internal view returns (bool) {
        PhEvm.TriggerCall[] memory calls = ph.matchingCalls(
            ph.getAssertionAdopter(), ICapGateVaultLike.redeem.selector, _successOnlyFilter(), MAX_MATCHING_CALLS
        );
        return calls.length > 0;
    }

    function _isWatchedAsset(address asset) internal view returns (bool) {
        return asset != address(0)
            && (asset == ASSET0 || asset == ASSET1 || asset == ASSET2 || asset == ASSET3 || asset == ASSET4);
    }

    function _addressArg(bytes memory input, uint256 argIndex) internal pure returns (address account) {
        uint256 offset = 4 + argIndex * 32;
        require(input.length >= offset + 32, "CapGate: malformed calldata");

        assembly {
            account := shr(96, mload(add(add(input, 0x20), offset)))
        }
    }
}
