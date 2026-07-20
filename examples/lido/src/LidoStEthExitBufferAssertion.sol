// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {LidoVaultHelpers} from "./LidoVaultHelpers.sol";
import {IWstETHLike} from "./LidoVaultInterfaces.sol";

/// @title LidoStEthExitBufferAssertion
/// @author Phylax Systems
/// @notice Keeps a Lido stETH vault's stETH withdrawable back to Lido: a standing buffer floor
///         plus a flow circuit breaker on stETH/wstETH outflows.
/// @dev Apply to the vault — the account that custodies the stETH/wstETH and deploys it.
///
///      This is the assertion Lido actually asked for: "some share of stETH always remains in a
///      state where it can be unstaked via Lido, never fully locked/deployed." On-chain that can
///      only be guaranteed in the REQUESTABLE sense — stETH a vault holds idle can be submitted to
///      Lido's WithdrawalQueue at any time. It cannot be guaranteed CLAIMABLE-instantly: claiming
///      is bounded by the Ethereum validator exit queue and Lido's own buffer, and each withdrawal
///      request is capped (≤ 1,000 ETH/request, larger amounts batch). So this assertion enforces
///      requestability, and leaves claim throughput where it actually lives — at the Lido protocol.
///
///      Two layers, configurable independently:
///      - **Buffer floor** (every transaction): the vault's idle, requestable stETH-equivalent —
///        idle stETH plus idle wstETH valued at `stEthPerToken()` — must stay above a floor. The
///        floor is the larger of an absolute minimum and a fraction of the vault's total
///        stETH-equivalent (idle + deployed), so the vault is provably never fully deployed.
///      - **Outflow circuit breaker** (rolling window): stETH and wstETH cannot leave the vault
///        faster than a configured fraction of balance per window. This is the Safe last-mile
///        defense — even if the vault's signer pipeline is fully compromised, a burst drain trips
///        the breaker and the transaction is never included.
contract LidoStEthExitBufferAssertion is LidoVaultHelpers {
    /// @notice Account custodying the vault's stETH/wstETH (the address whose buffer is protected).
    address public immutable vault;

    /// @notice stETH token. Counted at parity (1 stETH = 1 stETH-equivalent), requestable as-is.
    address public immutable stEth;

    /// @notice wstETH token. Valued through Lido's `stEthPerToken()`; unwraps to stETH atomically.
    address public immutable wstEth;

    /// @notice Receipt token for stETH-equivalent deployed out of idle custody (e.g. Aave awstETH).
    ///         Valued at `stEthPerToken()` to size total exposure. Zero counts only idle holdings.
    address public immutable deployedStEthReceipt;

    /// @notice Absolute floor of idle, requestable stETH-equivalent (stETH wei). Zero disables.
    ///         Capped at the vault's total stETH-equivalent so a small vault is never bricked.
    uint256 public immutable minIdleStEthEq;

    /// @notice Relative floor: idle stETH-equivalent must be at least this many bps of the vault's
    ///         total stETH-equivalent (idle + deployed). 500 = keep ≥5% requestable. Zero disables.
    uint256 public immutable minBufferBps;

    /// @notice Cumulative outflow cap for stETH/wstETH, in bps of the balance at window start.
    ///         1000 = at most 10% may leave per window. Zero disables the breaker entirely.
    uint256 public immutable outflowThresholdBps;

    /// @notice Rolling window length for the outflow breaker, in seconds.
    uint256 public immutable outflowWindowDuration;

    constructor(
        address vault_,
        address stEth_,
        address wstEth_,
        address deployedStEthReceipt_,
        uint256 minIdleStEthEq_,
        uint256 minBufferBps_,
        uint256 outflowThresholdBps_,
        uint256 outflowWindowDuration_
    ) {
        require(vault_ != address(0), "LidoVault: zero vault");
        require(stEth_ != address(0), "LidoVault: zero stETH");
        require(wstEth_ != address(0), "LidoVault: zero wstETH");
        require(minBufferBps_ <= 10_000, "LidoVault: buffer bps too large");
        require(outflowThresholdBps_ <= 10_000, "LidoVault: outflow bps too large");
        require(outflowThresholdBps_ == 0 || outflowWindowDuration_ != 0, "LidoVault: zero outflow window");

        vault = vault_;
        stEth = stEth_;
        wstEth = wstEth_;
        deployedStEthReceipt = deployedStEthReceipt_;
        minIdleStEthEq = minIdleStEthEq_;
        minBufferBps = minBufferBps_;
        outflowThresholdBps = outflowThresholdBps_;
        outflowWindowDuration = outflowWindowDuration_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires the per-transaction buffer floor and the rolling-window outflow breakers.
    /// @dev The buffer floor fires on every transaction touching the vault. The breakers register
    ///      only when configured; the executor tracks the rolling outflow and invokes the
    ///      assertion function solely when a token's outflow crosses the threshold.
    function triggers() external view override {
        // Intentionally empty. Independent stETH/wstETH net-flow watchers reject wrap, unwrap,
        // queue requests, and strategy moves while omitted assets let counted custody drain to zero.
    }

    /// @notice Requires the vault to end every transaction holding enough idle stETH-equivalent to
    ///         remain requestable to Lido.
    /// @dev Evaluated on post-transaction state. Idle (requestable) holdings are idle stETH plus
    ///      idle wstETH at the Lido rate; total exposure adds the deployed receipt at the same
    ///      rate. The required floor is the larger of the absolute minimum (capped at total, so it
    ///      can never demand more stETH than the vault holds) and the relative fraction of total.
    ///      A vault holding no stETH at all has nothing to reserve and passes — draining the last
    ///      of it is the outflow breaker's job, not the floor's. A failure means the transaction
    ///      left the vault more deployed than its exit policy allows.
    function assertWithdrawableBufferFloor() external view {
        PhEvm.ForkId memory fork = _postTx();

        uint256 rate = _readUintAt(wstEth, abi.encodeCall(IWstETHLike.stEthPerToken, ()), fork);
        require(rate != 0, "LidoVault: zero Lido rate");

        uint256 idle =
            _readBalanceAt(stEth, vault, fork) + ph.mulDivDown(_readBalanceAt(wstEth, vault, fork), rate, 1e18);

        uint256 total = idle;
        if (deployedStEthReceipt != address(0)) {
            total += ph.mulDivDown(_readBalanceAt(deployedStEthReceipt, vault, fork), rate, 1e18);
        }

        if (total == 0) {
            return;
        }

        uint256 requiredAbsolute = minIdleStEthEq < total ? minIdleStEthEq : total;
        uint256 requiredRelative = ph.mulDivUp(total, minBufferBps, 10_000);
        uint256 required = requiredAbsolute > requiredRelative ? requiredAbsolute : requiredRelative;

        require(idle >= required, "LidoVault: withdrawable stETH buffer below floor");
    }

    /// @notice Hard circuit breaker for stETH/wstETH outflows from the vault.
    /// @dev Invoked by the executor only once cumulative outflow of the watched token has crossed
    ///      `outflowThresholdBps` of the window-start balance — so reaching this function already
    ///      means the rate limit was breached. The breaker reverts unconditionally, so the
    ///      offending transaction is never included and the team is alerted to triage. Set the
    ///      window threshold generously: a legitimate planned unstake above it must be split or the
    ///      limit temporarily raised. A destination-aware variant (exempt transfers to Lido's
    ///      WithdrawalQueue, gate the rest) is a natural extension once transfer introspection is
    ///      wired in — `ph.outflowContext()` exposes the breaching token and the window totals.
    function assertOutflowWithinLimit() external pure {
        revert("LidoVault: stETH outflow circuit breaker tripped");
    }
}
