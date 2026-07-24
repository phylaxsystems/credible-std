// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {ZeroExSettlerMainnetSwapIntrospectionHelpers} from "./ZeroExSettlerMainnetSwapIntrospectionHelpers.sol";

/// @title ZeroExSettlerMainnetSwapIntrospectionAssertion
/// @author Phylax Systems
/// @notice Quarantined mainnet route-introspection prototype.
/// @dev Current and previous registered Settler generations accept codecs, fork IDs, repeated
///      legs, and route sizes this parser does not model. Descendant logs also cannot be assigned
///      causally to one decoded action. No production triggers are registered until an exact,
///      generation-specific codec and call-attribution model replaces this prototype.
contract ZeroExSettlerMainnetSwapIntrospectionAssertion is ZeroExSettlerMainnetSwapIntrospectionHelpers {
    constructor(address settler_, address registry_, uint128 featureId_, uint256 maxPriceImpactBps_)
        ZeroExSettlerMainnetSwapIntrospectionHelpers(settler_, registry_, featureId_, maxPriceImpactBps_)
    {}

    /// @notice Registers taker-submitted and meta-transaction Settler entry points.
    /// @dev Runs call-scoped so each internal swap call can be matched to the exact settlement
    ///      execution and compared against pre-call venue state.
    function triggers() external view override {
        // Intentionally empty. See the contract-level quarantine notice.
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
