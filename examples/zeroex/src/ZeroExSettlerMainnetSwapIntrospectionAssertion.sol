// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {IZeroExSettlerLike, IZeroExSettlerMetaTxnLike} from "./ZeroExSettlerInterfaces.sol";
import {ZeroExSettlerMainnetSwapIntrospectionHelpers} from "./ZeroExSettlerMainnetSwapIntrospectionHelpers.sol";

/// @title ZeroExSettlerMainnetSwapIntrospectionAssertion
/// @author Phylax Systems
/// @notice Detects severe intermediate price impact in Ethereum mainnet 0x Settler routes.
/// @dev The assertion:
///      - decodes mainnet Settler action bytes for each accepted settlement call;
///      - validates supported Uni V2, Uni V3 fork, and Uni V4 swap call outcomes;
///      - skips known mainnet actions whose spot/reference model is not safe in this example.
contract ZeroExSettlerMainnetSwapIntrospectionAssertion is ZeroExSettlerMainnetSwapIntrospectionHelpers {
    constructor(address settler_, address registry_, uint128 featureId_, uint256 maxPriceImpactBps_)
        ZeroExSettlerMainnetSwapIntrospectionHelpers(settler_, registry_, featureId_, maxPriceImpactBps_)
    {}

    /// @notice Registers taker-submitted and meta-transaction Settler entry points.
    /// @dev Runs call-scoped so each internal swap call can be matched to the exact settlement
    ///      execution and compared against pre-call venue state.
    function triggers() external view override {
        registerFnCallTrigger(this.assertMainnetSwapLegsWithinPriceImpact.selector, IZeroExSettlerLike.execute.selector);
        registerFnCallTrigger(
            this.assertMainnetSwapLegsWithinPriceImpact.selector, IZeroExSettlerLike.executeWithPermit.selector
        );
        registerFnCallTrigger(
            this.assertMainnetSwapLegsWithinPriceImpact.selector, IZeroExSettlerMetaTxnLike.executeMetaTxn.selector
        );
    }

    /// @notice Checks supported mainnet swap legs against pre-call spot/reference prices.
    /// @dev A failure means a supported internal venue call executed below the configured floor.
    ///      Unsupported mainnet actions are skipped explicitly rather than inferred from weak data.
    function assertMainnetSwapLegsWithinPriceImpact() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        _requireConfiguredSettlerIsAdopter();
        _assertMainnetActionsWithinPriceImpact(ctx.callStart);
    }
}
