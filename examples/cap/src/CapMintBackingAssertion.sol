// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {CapMintBackingHelpers} from "./CapMintBackingHelpers.sol";

/// @title CapMintBackingAssertion
/// @author Phylax Systems
/// @notice Keeps cUSD fully backed: supply may not grow without matching reserves, and
///         reserves may not be drained without matching cUSD burns ("no infinite mint").
/// @dev Two invariants over Cap's combined CapToken/Vault/FractionalReserve adopter:
///
///      1. Backing covers supply (`assertBackingCoversSupply`): on every supply-changing
///         operation (mint/burn/redeem), the USD value of all backing reserves
///         (`Σ totalSupplies(asset) * oraclePrice(asset)`) must still cover cUSD supply
///         valued at its $1 face peg. Checked as a non-worsening delta from PreTx to PostTx
///         so a pre-existing depeg does not penalize unrelated transactions, while any
///         transaction that mints cUSD without adding backing (or removes backing without
///         burning cUSD) trips it.
///
///      2. Reserve inflow accounted (`assertReserveInflowAccounted`): an inflow circuit
///         breaker that, once a backing asset's rolling inflow breaches the threshold,
///         requires the incoming balance to be reflected in protocol accounting. A direct
///         donation / reserve-stuffing inflow that is not booked as `totalSupplies` (e.g. to
///         skew the fractional-reserve share price) raises idle custody above accounting and
///         trips it. This complements the existing redemption gate, which only bounds outflow.
contract CapMintBackingAssertion is CapMintBackingHelpers {
    /// @dev Rounding/oracle headroom on the solvency floor, in bps of cUSD face value.
    uint256 internal constant SOLVENCY_TOLERANCE_BPS = 10;

    /// @dev Inflow circuit-breaker window and trip threshold (bps of window-start TVL).
    uint256 internal constant INFLOW_WINDOW = 1 hours;
    uint256 internal constant INFLOW_TRIGGER_BPS = 2_000;

    /// @dev Allowed jump in unaccounted idle slack on a breaching tx, bps of window-start TVL.
    uint256 internal constant INFLOW_SLACK_TOLERANCE_BPS = 50;

    constructor(address oracle_, address asset0_, address asset1_, address asset2_, address asset3_, address asset4_)
        CapMintBackingHelpers(oracle_, asset0_, asset1_, asset2_, asset3_, asset4_)
    {
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    /// @dev Intentionally unarmed. Cap values cUSD with its live NAV conversion rather than at a
    ///      fixed one-dollar face value, and its reserve set is mutable. The policy helpers below
    ///      are retained as a prototype, but registering them would reject valid mint, burn, and
    ///      proportional redemption paths and would miss newly added reserves.
    function triggers() external view override {
        // Quarantined until the assertion derives Cap's current NAV and reserve set on-chain.
    }

    /// @notice cUSD backing may not be eroded across a supply-changing operation.
    /// @dev Enforces conservation, not just a solvency floor: a single transaction may not lower
    ///      the reserve-over-cUSD surplus beyond tolerance, whether the protocol starts over- or
    ///      under-collateralized. Honest mint/burn/redeem add or remove equal value on both sides,
    ///      so surplus stays flat and they pass; an unbacked mint (or backing drained without a
    ///      matching burn) lowers surplus and trips. Checking non-worsening in *both* sign branches
    ///      closes the "no infinite mint" hole where a single tx could consume the entire
    ///      over-collateralization buffer while still ending non-negative. A pre-existing depeg is
    ///      tolerated (the bound is relative to `surplusPre`) so unrelated txs are not penalized.
    function assertBackingCoversSupply() external view {
        int256 surplusPre = _surplusUsd8(_preTx());
        int256 surplusPost = _surplusUsd8(_postTx());

        // forge-lint: disable-next-line(unsafe-typecast) — USD-8 tolerance is far below int256 max
        int256 tolerance = int256(_capFaceValueUsd8(_preTx()) * SOLVENCY_TOLERANCE_BPS / 10_000);

        require(surplusPost >= surplusPre - tolerance, "CapBacking: backing conservation violated");
    }

    /// @notice A surge of incoming backing must be booked as protocol accounting.
    /// @dev Triggered by the cumulative-inflow breaker on a backing asset. Fails when the
    ///      breaching transaction raises idle custody without a matching increase in
    ///      accounted backing (totalSupplies net of borrows/loaned), i.e. an unaccounted
    ///      donation or reserve-stuffing inflow.
    function assertReserveInflowAccounted() external view {
        PhEvm.InflowContext memory ctx = ph.inflowContext();
        require(ctx.token != address(0), "CapBacking: no inflow context");

        int256 slackPre = _idleSlack(ctx.token, _preTx());
        int256 slackPost = _idleSlack(ctx.token, _postTx());

        // forge-lint: disable-next-line(unsafe-typecast) — TVL-derived tolerance is far below int256 max
        int256 tolerance = int256(ctx.tvlSnapshot * INFLOW_SLACK_TOLERANCE_BPS / 10_000);
        require(slackPost <= slackPre + tolerance, "CapBacking: unaccounted reserve inflow");
    }

    function _watchInflow(address asset) internal view {
        if (asset == address(0)) return;
        watchCumulativeInflow(asset, INFLOW_TRIGGER_BPS, INFLOW_WINDOW, this.assertReserveInflowAccounted.selector);
    }
}
