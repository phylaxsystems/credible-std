// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {MellowCuratorHelpers} from "./MellowCuratorHelpers.sol";

/// @title MellowSubvaultAllocationAssertion
/// @author Phylax Systems
/// @notice Blocks a Mellow subvault from allocating into a lending market it could not exit.
/// @dev Apply to the `Subvault` (the account that custodies a deployed position and makes the
///      market calls through `CallModule.call`).
///
///      WHY THIS IS NOT A RESTATEMENT. Mellow already restricts *which* market actions a subvault
///      may take: every `Subvault.call` is gated by the per-subvault `Verifier`
///      (`CALLER_ROLE` + a Merkle root / on-chain allowlist / custom verifier), so "this subvault
///      may only deposit into Aave pool X" is enforced on-chain. But the Verifier authorizes the
///      *call*, never the *state of the market*: it will happily let an approved `supply` land in a
///      reserve that has been borrowed down to near-100% utilization. Aave does not guard this at
///      deposit time either — illiquidity only bites on withdraw. So neither layer stops a curator
///      (honest, careless, or compromised) from parking vault funds in a market they cannot pull
///      back out of. This assertion adds exactly that missing check, in external state.
///
///      The invariant. Whenever a transaction grows the subvault's supplied position in the watched
///      lending market, the market must still hold, after the allocation, at least
///      `minExitLiquidityBps` of that position in immediately-withdrawable liquidity (the underlying
///      balance custodied by the supply receipt / aToken). Reducing or holding the position is
///      always allowed — only *adding* exposure into an illiquid market trips. Withdrawable
///      liquidity and supplied balance are read as plain ERC-20 balances, so the check works for any
///      Aave-v3-like reserve without decoding pool internals.
///
///      Ceiling, stated honestly: this guards exit-ability of an on-chain lending allocation. It is
///      not a solvency or bad-debt oracle, and it deliberately does not assess restaking subvaults
///      (Symbiotic/EigenLayer), whose health lives off-chain. Deploy one instance per watched
///      (asset, market) pair. Calibrate `minExitLiquidityBps` to the fraction of a position the
///      vault must be able to unwind on demand (10_000 = the full position must stay withdrawable).
contract MellowSubvaultAllocationAssertion is MellowCuratorHelpers {
    /// @notice Subvault whose allocations are guarded (the assertion adopter).
    address public immutable subvault;

    /// @notice Underlying asset supplied into the market; its balance held by `aToken` is the
    ///         immediately-withdrawable reserve liquidity.
    address public immutable asset;

    /// @notice Supply receipt for the watched market (e.g. the Aave aToken). Its
    ///         `balanceOf(subvault)` is the subvault's supplied position; it also custodies the
    ///         withdrawable `asset` liquidity.
    address public immutable aToken;

    /// @notice Required withdrawable liquidity after an allocation, in bps of the subvault's
    ///         post-allocation supplied position. 10_000 = the whole position must stay withdrawable.
    ///         CALIBRATE: the fraction the vault must be able to unwind on demand for this market.
    uint256 public immutable minExitLiquidityBps;

    constructor(address subvault_, address asset_, address aToken_, uint256 minExitLiquidityBps_) {
        require(subvault_ != address(0), "MellowSubvault: zero subvault");
        require(asset_ != address(0), "MellowSubvault: zero asset");
        require(aToken_ != address(0), "MellowSubvault: zero aToken");
        require(minExitLiquidityBps_ != 0, "MellowSubvault: zero exit liquidity bps");

        subvault = subvault_;
        asset = asset_;
        aToken = aToken_;
        minExitLiquidityBps = minExitLiquidityBps_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Checks every subvault transaction at its boundary.
    /// @dev Fires at transaction end so the check is agnostic to how the allocation was routed
    ///      through `CallModule.call`; the exposure-growth gate below means it only enforces when an
    ///      allocation actually happened. Pre-tx and post-tx share a block timestamp, so the supply
    ///      receipt balance moves only on a real supply/withdraw, never on interest accrual.
    function triggers() external view override {
        registerTxEndTrigger(this.assertHealthyAllocation.selector);
    }

    /// @notice Requires a transaction that grows the subvault's supplied position to leave the
    ///         market liquid enough to exit.
    /// @dev Compares the subvault's supply-receipt balance across the pre/post-tx snapshots. If it
    ///      did not grow, the allocation envelope has nothing to enforce (reducing or holding is
    ///      always safe). When it grew, the market's withdrawable liquidity (the underlying balance
    ///      held by the supply receipt) must cover the configured fraction of the new position. A
    ///      failure means the transaction parked more of the vault's funds in a market that cannot
    ///      currently be unwound.
    function assertHealthyAllocation() external view {
        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();

        uint256 preSupplied = _readBalanceAt(aToken, subvault, pre);
        uint256 postSupplied = _readBalanceAt(aToken, subvault, post);
        if (postSupplied <= preSupplied) {
            return;
        }

        uint256 withdrawable = _readBalanceAt(asset, aToken, post);
        require(
            withdrawable >= ph.mulDivUp(postSupplied, minExitLiquidityBps, 10_000),
            "MellowSubvault: allocation into illiquid market"
        );
    }
}
