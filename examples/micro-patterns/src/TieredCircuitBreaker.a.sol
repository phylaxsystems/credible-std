// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface ILiquidationPath {
    function liquidate(address account) external;
}

interface IUserExitPath {
    function withdraw(uint256 amount) external;
    function redeem(uint256 shares) external;
}

/// @notice A two-tier outflow breaker: soft breach becomes liquidation-only, hard breach stops everything.
/// @dev Protects against bank-run or exploit-style asset flight:
///      - ordinary withdrawals/redeems continuing after a rolling outflow breach;
///      - new net outflow that is not part of a configured liquidation path;
///      - catastrophic outflow that should halt all touching transactions until the window recovers.
contract TieredCircuitBreakerAssertion is Assertion {
    address public immutable ASSET;
    address public immutable LIQUIDATION_TARGET;

    uint256 public constant SOFT_THRESHOLD_BPS = 1_000;
    uint256 public constant HARD_THRESHOLD_BPS = 3_000;
    uint256 public constant WINDOW = 24 hours;

    constructor(address asset_, address liquidationTarget_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
        ASSET = asset_;
        LIQUIDATION_TARGET = liquidationTarget_;
    }

    function triggers() external view override {
        watchCumulativeOutflow(ASSET, SOFT_THRESHOLD_BPS, WINDOW, this.assertSoftBreaker.selector);
        watchCumulativeOutflow(ASSET, HARD_THRESHOLD_BPS, WINDOW, this.assertHardBreaker.selector);
    }

    function assertSoftBreaker() external view {
        PhEvm.OutflowContext memory ctx = ph.outflowContext();
        require(ctx.token == ASSET, "wrong asset");

        // Failure scenario: the vault is already in stress and a user exit would deepen the run.
        require(!_hasUserExit(), "user exits blocked during outflow breach");

        // Healing transactions such as deposits or neutral accounting updates should remain live.
        if (_currentTxNetOutflow() == 0) {
            return;
        }

        // Failure scenario: more assets leave custody without an approved liquidation reason.
        require(_hasLiquidation(), "new outflow requires liquidation");
    }

    function assertHardBreaker() external pure {
        // Failure scenario: the larger outflow tier is breached, so reduce-only is no longer enough.
        revert("hard outflow breaker tripped");
    }

    function _hasLiquidation() internal view returns (bool) {
        return _matchingCalls(LIQUIDATION_TARGET, ILiquidationPath.liquidate.selector, 1).length != 0;
    }

    function _hasUserExit() internal view returns (bool) {
        address vault = ph.getAssertionAdopter();
        return _matchingCalls(vault, IUserExitPath.withdraw.selector, 1).length != 0
            || _matchingCalls(vault, IUserExitPath.redeem.selector, 1).length != 0;
    }

    function _currentTxNetOutflow() internal view returns (uint256 netOutflow) {
        address vault = ph.getAssertionAdopter();
        PhEvm.Erc20TransferData[] memory deltas = ph.reduceErc20BalanceDeltas(ASSET, _postTx());
        uint256 outflow;
        uint256 inflow;

        for (uint256 i; i < deltas.length; ++i) {
            if (deltas[i].from == vault) outflow += deltas[i].value;
            if (deltas[i].to == vault) inflow += deltas[i].value;
        }

        return outflow > inflow ? outflow - inflow : 0;
    }
}
