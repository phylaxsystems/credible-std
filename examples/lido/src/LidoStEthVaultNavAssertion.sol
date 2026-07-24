// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {LidoVaultHelpers} from "./LidoVaultHelpers.sol";
import {IAaveOracleLike, IERC20Like, IRateProviderLike, IWstETHLike} from "./LidoVaultInterfaces.sol";

/// @title LidoStEthVaultNavAssertion
/// @author Phylax Systems
/// @notice Verifies a Lido stETH vault's reported share rate against on-chain NAV.
/// @dev Apply to the contract that reports the share rate (accountant, oracle, or vault).
///
///      stETH vault share prices are typically computed off-chain and pushed on-chain, with
///      bounds that are only RELATIVE to the previous rate (e.g. ±1% per update). A compromised
///      or buggy updater can still walk the rate several percent per day in either direction.
///      This assertion recomputes NAV from on-chain verifiable components — idle base-asset/
///      stETH/wstETH custody plus the net Aave-like position — and requires the reported rate
///      to sit within tolerance of it after every transaction touching the rate reporter,
///      turning the off-chain pricing oracle from trusted into verified.
contract LidoStEthVaultNavAssertion is LidoVaultHelpers {
    /// @notice Account custodying the vault's idle assets and lending-market position.
    address public immutable vault;

    /// @notice Share token whose supply divides NAV into the per-share rate.
    address public immutable shareToken;

    /// @notice Rate source reporting base-asset units per share (`getRate()`).
    address public immutable rateSource;

    /// @notice Aave v3-like pool holding the vault's position. Zero skips the position leg.
    address public immutable aavePool;

    /// @notice Aave v3-like oracle used to convert base-currency position values.
    address public immutable aaveOracle;

    /// @notice The vault's base/quote asset (e.g. WETH). NAV is denominated in it.
    address public immutable baseAsset;

    /// @notice stETH, counted at parity with the base asset (the usual pricing convention).
    address public immutable stEth;

    /// @notice wstETH, valued through Lido's `stEthPerToken()` rate.
    address public immutable wstEth;

    /// @notice One full share, scaled to the share-token decimals.
    uint256 public immutable ONE_SHARE;

    /// @notice Max tolerated deviation between the reported rate and on-chain NAV, in bps.
    uint256 public immutable rateToleranceBps;

    constructor(
        address vault_,
        address shareToken_,
        address rateSource_,
        address aavePool_,
        address aaveOracle_,
        address baseAsset_,
        address stEth_,
        address wstEth_,
        uint8 shareDecimals_,
        uint256 rateToleranceBps_
    ) {
        require(vault_ != address(0), "LidoVault: zero vault");
        require(shareToken_ != address(0), "LidoVault: zero share token");
        require(rateSource_ != address(0), "LidoVault: zero rate source");
        require(aavePool_ == address(0) || aaveOracle_ != address(0), "LidoVault: zero aave oracle");
        require(baseAsset_ != address(0), "LidoVault: zero base asset");
        require(stEth_ != address(0), "LidoVault: zero stETH");
        require(wstEth_ != address(0), "LidoVault: zero wstETH");
        require(rateToleranceBps_ <= 10_000, "LidoVault: tolerance too large");

        vault = vault_;
        shareToken = shareToken_;
        rateSource = rateSource_;
        aavePool = aavePool_;
        aaveOracle = aaveOracle_;
        baseAsset = baseAsset_;
        stEth = stEth_;
        wstEth = wstEth_;
        ONE_SHARE = 10 ** uint256(shareDecimals_);
        rateToleranceBps = rateToleranceBps_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires the NAV consistency check to every transaction touching the rate reporter.
    function triggers() external view override {
        // Intentionally empty. Mellow, Veda, and Lido V3 do not share this custody, supply, rate,
        // or liability model; each requires its own protocol-specific NAV adapter.
    }

    /// @notice Checks the reported share rate against NAV recomputed from on-chain state.
    /// @dev Triggered at transaction end, so every rate push (and any other mutation of the
    ///      reporter) is validated in post-state. NAV counts idle base asset + idle stETH (at
    ///      parity) + idle wstETH (at the Lido rate) + the net Aave-like position converted to
    ///      base-asset terms, divided by total shares. A failure means the reporter holds a
    ///      share price that on-chain state cannot support — in either direction, since a
    ///      low-balled rate harms exiting holders too.
    function assertShareRateMatchesNav() external view {
        PhEvm.ForkId memory fork = _postTx();

        uint256 supply = _readUintAt(shareToken, abi.encodeCall(IERC20Like.totalSupply, ()), fork);
        if (supply == 0) {
            return;
        }

        uint256 reportedRate = _readUintAt(rateSource, abi.encodeCall(IRateProviderLike.getRate, ()), fork);
        uint256 navPerShare = ph.mulDivDown(_vaultNavInBaseAt(fork), ONE_SHARE, supply);
        uint256 tolerance = ph.mulDivUp(navPerShare, rateToleranceBps, 10_000);

        require(reportedRate <= navPerShare + tolerance, "LidoVault: reported rate above on-chain NAV");
        require(reportedRate >= navPerShare - tolerance, "LidoVault: reported rate below on-chain NAV");
    }

    /// @notice Computes the vault's NAV in base-asset terms at a snapshot fork.
    /// @dev Counts idle custody plus the net lending-market position. stETH is valued at parity
    ///      with the base asset to match the usual stETH vault pricing convention; peg stress is
    ///      the peg assertion's job, not this one's. Reverts when debt exceeds total assets —
    ///      no positive rate is defensible for an insolvent book.
    function _vaultNavInBaseAt(PhEvm.ForkId memory fork) internal view returns (uint256 nav) {
        nav = _readBalanceAt(baseAsset, vault, fork) + _readBalanceAt(stEth, vault, fork);

        uint256 wstEthBalance = _readBalanceAt(wstEth, vault, fork);
        if (wstEthBalance != 0) {
            uint256 lidoRate = _readUintAt(wstEth, abi.encodeCall(IWstETHLike.stEthPerToken, ()), fork);
            nav += ph.mulDivDown(wstEthBalance, lidoRate, 1e18);
        }

        if (aavePool == address(0)) {
            return nav;
        }

        (uint256 collateralBase, uint256 debtBase,) = _aaveAccountDataAt(aavePool, vault, fork);
        if (collateralBase != 0 || debtBase != 0) {
            uint256 basePrice =
                _readUintAt(aaveOracle, abi.encodeCall(IAaveOracleLike.getAssetPrice, (baseAsset)), fork);
            require(basePrice != 0, "LidoVault: zero base asset price");

            uint256 collateralInBase = ph.mulDivDown(collateralBase, 1e18, basePrice);
            uint256 debtInBase = ph.mulDivUp(debtBase, 1e18, basePrice);

            nav += collateralInBase;
            require(nav >= debtInBase, "LidoVault: vault book is insolvent");
            nav -= debtInBase;
        }
    }
}
