// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {LidoVaultHelpers} from "./LidoVaultHelpers.sol";
import {IERC20Like, IRateProviderLike, IWstETHLike} from "./LidoVaultInterfaces.sol";

/// @title LidoStEthVaultPegAssertion
/// @author Phylax Systems
/// @notice Entry/exit pricing safety for a Lido stETH vault during peg stress.
/// @dev Apply to the vault share token (or whichever contract mints and burns shares).
///
///      Most stETH vault stacks price stETH at parity with ETH and value wstETH purely from
///      Lido's `stEthPerToken()` — no market price enters the share-pricing path. During a
///      market depeg shares keep minting and burning at a fictional parity price, mispricing
///      depositors and exiters against remaining holders. Instead of watching stack-specific
///      deposit selectors, this assertion observes the share supply itself:
///      - any transaction that changes share supply (a mint or burn through any path) reverts
///        while the stETH/ETH market price is outside the peg band;
///      - the wstETH pricing source must match Lido's protocol rate and must not decrease
///        within a transaction (manipulation guard — `stEthPerToken` only drops on slashing).
contract LidoStEthVaultPegAssertion is LidoVaultHelpers {
    /// @notice Share token whose supply changes mark entries and exits.
    address public immutable shareToken;

    /// @notice Chainlink stETH/ETH market-price feed. Zero address disables depeg gating.
    address public immutable stEthEthFeed;

    /// @notice One unit of the stETH/ETH feed answer (10^feedDecimals).
    uint256 public immutable pegUnit;

    /// @notice Max tolerated stETH/ETH deviation from peg, in bps, for entries and exits.
    uint256 public immutable maxEntryDepegBps;

    /// @notice Max age, in seconds, the stETH/ETH feed answer may have before entries and exits are
    ///         gated as a depeg (fails closed). Zero keeps only the round-integrity checks.
    uint256 public immutable maxFeedStalenessSecs;

    /// @notice wstETH token, the source of Lido's protocol exchange rate.
    address public immutable wstEth;

    /// @notice Rate provider the vault uses to price wstETH. Zero disables the mismatch check.
    address public immutable wstEthRateProvider;

    /// @notice Max tolerated provider-vs-protocol rate mismatch in bps. Zero requires equality.
    uint256 public immutable maxProviderMismatchBps;

    constructor(
        address shareToken_,
        address stEthEthFeed_,
        uint8 stEthEthFeedDecimals_,
        uint256 maxEntryDepegBps_,
        uint256 maxFeedStalenessSecs_,
        address wstEth_,
        address wstEthRateProvider_,
        uint256 maxProviderMismatchBps_
    ) {
        require(shareToken_ != address(0), "LidoVault: zero share token");
        require(wstEth_ != address(0), "LidoVault: zero wstETH");

        shareToken = shareToken_;
        stEthEthFeed = stEthEthFeed_;
        pegUnit = 10 ** uint256(stEthEthFeedDecimals_);
        maxEntryDepegBps = maxEntryDepegBps_;
        maxFeedStalenessSecs = maxFeedStalenessSecs_;
        wstEth = wstEth_;
        wstEthRateProvider = wstEthRateProvider_;
        maxProviderMismatchBps = maxProviderMismatchBps_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires the supply-change depeg gate and the wstETH rate-integrity check.
    function triggers() external view override {
        // Intentionally empty. Supply changes are not the pricing boundary for asynchronous
        // Mellow flows, and blocking burns during depeg prevents legitimate exits and recovery.
    }

    /// @notice Checks that shares are not minted or burned while stETH trades off peg.
    /// @dev Triggered at transaction end. Watching the share supply instead of deposit/withdraw
    ///      selectors covers every entry and exit path — tellers, queues, solvers, or direct
    ///      mint/burn — on any vault stack. A failure means someone entered or exited the vault
    ///      at a parity-marked share price during a market depeg.
    function assertMintBurnPegSafety() external view {
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        uint256 preSupply = _readUintAt(shareToken, abi.encodeCall(IERC20Like.totalSupply, ()), preFork);
        uint256 postSupply = _readUintAt(shareToken, abi.encodeCall(IERC20Like.totalSupply, ()), postFork);

        if (preSupply == postSupply) {
            return;
        }

        require(
            !_isStEthDepeggedAt(stEthEthFeed, pegUnit, maxEntryDepegBps, maxFeedStalenessSecs, preFork)
                && !_isStEthDepeggedAt(stEthEthFeed, pegUnit, maxEntryDepegBps, maxFeedStalenessSecs, postFork),
            "LidoVault: stETH off peg, share pricing unsafe"
        );
    }

    /// @notice Checks the vault's wstETH pricing source against Lido's protocol rate.
    /// @dev Triggered at transaction end. The provider rate must match `stEthPerToken()` within
    ///      tolerance and must not decrease within the transaction — `stEthPerToken` only drops
    ///      on slashing, never as a side effect of a vault interaction. A failure means the
    ///      rate provider was substituted, manipulated, or desynced from the Lido rate while
    ///      shares were being priced.
    function assertWstEthRateIntegrity() external view {
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        uint256 preProtocolRate = _readUintAt(wstEth, abi.encodeCall(IWstETHLike.stEthPerToken, ()), preFork);
        uint256 postProtocolRate = _readUintAt(wstEth, abi.encodeCall(IWstETHLike.stEthPerToken, ()), postFork);

        require(postProtocolRate >= preProtocolRate, "LidoVault: wstETH rate decreased in transaction");
        require(postProtocolRate != 0, "LidoVault: zero protocol rate");

        if (wstEthRateProvider == address(0)) {
            return;
        }

        uint256 providerRate = _readUintAt(wstEthRateProvider, abi.encodeCall(IRateProviderLike.getRate, ()), postFork);
        uint256 mismatch =
            providerRate > postProtocolRate ? providerRate - postProtocolRate : postProtocolRate - providerRate;
        require(
            mismatch * 10_000 <= postProtocolRate * maxProviderMismatchBps,
            "LidoVault: rate provider desynced from Lido rate"
        );
    }
}
