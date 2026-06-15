// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {LidoVaultHelpers} from "./LidoVaultHelpers.sol";

/// @title LidoStEthVaultRiskAssertion
/// @author Phylax Systems
/// @notice Position risk policy for a Lido stETH vault looping through an Aave v3-like market.
/// @dev Apply to the contract whose transactions move the vault's position — the vault itself,
///      or its manager/strategy executor when allocations run through a separate contract.
///
///      Lending-market whitelists and vault permission systems constrain WHICH calls a strategist
///      may make; nothing on-chain constrains the STATE those calls are made into. This assertion
///      adds that layer, entirely at transaction boundaries so it works on any vault stack:
///      - reduce-only regime: when the position is already below the comfort band, stETH trades
///        off peg, or the share-pricing source cannot report a rate, a transaction may not grow
///        debt or lower the health factor;
///      - exit-liquidity guard: a transaction that grows debt must leave the borrowed reserve
///        liquid enough for the vault to unwind (market-health check at allocation time);
///      - collateral withdrawability guard: a transaction that deepens the supplied position
///        must leave the collateral reserve holding enough un-borrowed collateral for the
///        vault to pull its stETH back out on demand, and an already-illiquid collateral
///        reserve forces the same reduce-only regime as a depeg;
///      - position envelope: the health factor ends every transaction above a hard floor, may
///        only decline while staying inside the comfort band, and the raw collateral/debt
///        ratio holds a minimum.
///
///      Together these are what justify running the vault with thinner idle buffers: every
///      allocation carries an on-chain proof, at execution time, that it can be unwound.
contract LidoStEthVaultRiskAssertion is LidoVaultHelpers {
    /// @notice Account holding the lending-market position (the vault's custody address).
    address public immutable vault;

    /// @notice Aave v3-like pool holding the vault's looped position.
    address public immutable aavePool;

    /// @notice Chainlink stETH/ETH market-price feed. Zero address disables depeg detection.
    address public immutable stEthEthFeed;

    /// @notice One unit of the stETH/ETH feed answer (10^feedDecimals).
    uint256 public immutable pegUnit;

    /// @notice Max tolerated stETH/ETH deviation from peg, in bps, before reduce-only mode.
    uint256 public immutable maxDepegBps;

    /// @notice Max age, in seconds, the stETH/ETH feed answer may have before it is treated as a
    ///         depeg (fails closed into reduce-only). Zero keeps only the round-integrity checks.
    uint256 public immutable maxFeedStalenessSecs;

    /// @notice Share-pricing rate source; unreadable rate forces reduce-only. Zero disables.
    address public immutable rateSource;

    /// @notice Asset of the vault's borrowed leg. Zero disables the exit-liquidity guard.
    address public immutable borrowedAsset;

    /// @notice Reserve custody of the borrowed asset (e.g. the aToken); its underlying balance
    ///         is the liquidity available for the vault to unwind against.
    address public immutable borrowedAssetReserve;

    /// @notice Debt token tracking the vault's borrowed amount (e.g. the variable-debt token).
    address public immutable borrowedAssetDebtToken;

    /// @notice Asset supplied as collateral (e.g. wstETH). Zero disables the withdrawability guard.
    address public immutable collateralAsset;

    /// @notice Reserve custody of the collateral asset; its underlying balance is the
    ///         un-borrowed collateral available for the vault to withdraw (for Aave, the aToken).
    address public immutable collateralAssetReserve;

    /// @notice Receipt token tracking the vault's supplied collateral (for Aave, also the aToken).
    address public immutable collateralAssetSupplyToken;

    /// @notice Hard health-factor floor the vault may never end a transaction below (1e18 scale).
    uint256 public immutable minHealthFactor;

    /// @notice Comfort band: below this health factor the position is reduce-only (1e18 scale).
    uint256 public immutable reduceOnlyHealthFactor;

    /// @notice Minimum collateral/debt ratio in bps of 1e4 (e.g. 10_500 = 1.05x). Zero disables.
    uint256 public immutable minCollateralRatioBps;

    /// @notice Required reserve liquidity for new debt, in bps of the vault's debt. Zero disables.
    uint256 public immutable minExitLiquidityBps;

    /// @notice Required withdrawable collateral, in bps of the vault's supplied collateral.
    ///         Zero disables the withdrawability guard.
    uint256 public immutable minCollateralLiquidityBps;

    /// @notice Deployment configuration; see the matching immutables for field semantics.
    struct RiskConfig {
        address vault;
        address aavePool;
        address stEthEthFeed;
        uint8 stEthEthFeedDecimals;
        uint256 maxDepegBps;
        uint256 maxFeedStalenessSecs;
        address rateSource;
        address borrowedAsset;
        address borrowedAssetReserve;
        address borrowedAssetDebtToken;
        address collateralAsset;
        address collateralAssetReserve;
        address collateralAssetSupplyToken;
        uint256 minHealthFactor;
        uint256 reduceOnlyHealthFactor;
        uint256 minCollateralRatioBps;
        uint256 minExitLiquidityBps;
        uint256 minCollateralLiquidityBps;
    }

    constructor(RiskConfig memory config) {
        require(config.vault != address(0), "LidoVault: zero vault");
        require(config.aavePool != address(0), "LidoVault: zero pool");
        require(config.minHealthFactor >= 1e18, "LidoVault: floor below liquidation");
        require(config.reduceOnlyHealthFactor >= config.minHealthFactor, "LidoVault: band below floor");
        if (config.minExitLiquidityBps != 0) {
            require(config.borrowedAsset != address(0), "LidoVault: zero borrowed asset");
            require(config.borrowedAssetReserve != address(0), "LidoVault: zero borrowed reserve");
            require(config.borrowedAssetDebtToken != address(0), "LidoVault: zero borrowed debt token");
        }
        if (config.minCollateralLiquidityBps != 0) {
            require(config.collateralAsset != address(0), "LidoVault: zero collateral asset");
            require(config.collateralAssetReserve != address(0), "LidoVault: zero collateral reserve");
            require(config.collateralAssetSupplyToken != address(0), "LidoVault: zero collateral supply token");
        }

        vault = config.vault;
        aavePool = config.aavePool;
        stEthEthFeed = config.stEthEthFeed;
        pegUnit = 10 ** uint256(config.stEthEthFeedDecimals);
        maxDepegBps = config.maxDepegBps;
        maxFeedStalenessSecs = config.maxFeedStalenessSecs;
        rateSource = config.rateSource;
        borrowedAsset = config.borrowedAsset;
        borrowedAssetReserve = config.borrowedAssetReserve;
        borrowedAssetDebtToken = config.borrowedAssetDebtToken;
        collateralAsset = config.collateralAsset;
        collateralAssetReserve = config.collateralAssetReserve;
        collateralAssetSupplyToken = config.collateralAssetSupplyToken;
        minHealthFactor = config.minHealthFactor;
        reduceOnlyHealthFactor = config.reduceOnlyHealthFactor;
        minCollateralRatioBps = config.minCollateralRatioBps;
        minExitLiquidityBps = config.minExitLiquidityBps;
        minCollateralLiquidityBps = config.minCollateralLiquidityBps;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires the tx-wide risk regime and position envelope checks.
    function triggers() external view override {
        registerTxEndTrigger(this.assertRiskRegime.selector);
        registerTxEndTrigger(this.assertPositionEnvelope.selector);
    }

    /// @notice Checks that risk only grows in a healthy position under trustworthy pricing
    ///         and that every position deepening keeps the collateral withdrawable on demand.
    /// @dev Triggered at transaction end. Reduce-only mode is entered when the pre-transaction
    ///      health factor sits below the comfort band, the stETH/ETH market price has left the
    ///      peg band, the rate source cannot price shares, or the collateral reserve no longer
    ///      holds enough un-borrowed collateral for the vault to withdraw. In that regime debt
    ///      must not grow and the health factor must not decline; when the trigger is market
    ///      conditions (shaky pricing or illiquid collateral) rather than the vault's own
    ///      health, the supplied collateral may not grow either — supplying more into a market
    ///      the vault might not get back out of is itself risky behaviour. Independently, any
    ///      transaction that grows debt must leave the borrowed reserve liquid enough to
    ///      unwind, and any transaction that deepens the supplied position must leave the
    ///      collateral reserve liquid enough to withdraw it. A failure means new risk was
    ///      added into an unhealthy position, a shaky oracle regime, or an illiquid market.
    function assertRiskRegime() external view {
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        (, uint256 preDebt, uint256 preHf) = _aaveAccountDataAt(aavePool, vault, preFork);
        (, uint256 postDebt, uint256 postHf) = _aaveAccountDataAt(aavePool, vault, postFork);

        bool unhealthy = preDebt != 0 && preHf < reduceOnlyHealthFactor;
        bool shaky = _isStEthDepeggedAt(stEthEthFeed, pegUnit, maxDepegBps, maxFeedStalenessSecs, preFork)
            || !_canReadRateAt(rateSource, preFork);
        bool illiquid = _collateralIlliquidAt(preFork);

        if (unhealthy || shaky || illiquid) {
            require(postDebt <= preDebt, "LidoVault: reduce-only regime, debt increased");
            if (postDebt != 0) {
                require(postHf >= preHf, "LidoVault: reduce-only regime, health factor declined");
            }
        }

        uint256 preSupplied;
        uint256 postSupplied;
        if (collateralAssetSupplyToken != address(0)) {
            preSupplied = _readBalanceAt(collateralAssetSupplyToken, vault, preFork);
            postSupplied = _readBalanceAt(collateralAssetSupplyToken, vault, postFork);
        }

        if (shaky || illiquid) {
            require(postSupplied <= preSupplied, "LidoVault: reduce-only regime, collateral exposure increased");
        }

        if (minExitLiquidityBps != 0 && postDebt > preDebt) {
            uint256 vaultDebt = _readBalanceAt(borrowedAssetDebtToken, vault, postFork);
            uint256 reserveLiquidity = _readBalanceAt(borrowedAsset, borrowedAssetReserve, postFork);
            require(
                reserveLiquidity >= ph.mulDivUp(vaultDebt, minExitLiquidityBps, 10_000),
                "LidoVault: insufficient exit liquidity for new debt"
            );
        }

        if (minCollateralLiquidityBps != 0 && postSupplied > preSupplied) {
            uint256 withdrawable = _readBalanceAt(collateralAsset, collateralAssetReserve, postFork);
            require(
                withdrawable >= ph.mulDivUp(postSupplied, minCollateralLiquidityBps, 10_000),
                "LidoVault: collateral not withdrawable on demand"
            );
        }
    }

    /// @notice Returns whether the collateral reserve can no longer cover the vault's exit.
    /// @dev Compares the reserve's un-borrowed collateral against the configured fraction of
    ///      what the vault has supplied. Disabled (always liquid) when unconfigured or when
    ///      the vault has no supplied position.
    function _collateralIlliquidAt(PhEvm.ForkId memory fork) internal view returns (bool) {
        if (minCollateralLiquidityBps == 0) {
            return false;
        }

        uint256 supplied = _readBalanceAt(collateralAssetSupplyToken, vault, fork);
        if (supplied == 0) {
            return false;
        }

        uint256 withdrawable = _readBalanceAt(collateralAsset, collateralAssetReserve, fork);
        return withdrawable < ph.mulDivUp(supplied, minCollateralLiquidityBps, 10_000);
    }

    /// @notice Checks the vault's position envelope after every transaction.
    /// @dev Triggered at transaction end. The health factor must end above the hard floor, may
    ///      only decline while remaining inside the comfort band, and the raw collateral/debt
    ///      ratio must hold its minimum. A failure means the transaction left the looped
    ///      position closer to liquidation than the configured policy allows.
    function assertPositionEnvelope() external view {
        PhEvm.ForkId memory preFork = _preTx();
        PhEvm.ForkId memory postFork = _postTx();

        (,, uint256 preHf) = _aaveAccountDataAt(aavePool, vault, preFork);
        (uint256 postCollateral, uint256 postDebt, uint256 postHf) = _aaveAccountDataAt(aavePool, vault, postFork);

        if (postDebt == 0) {
            return;
        }

        require(postHf >= minHealthFactor, "LidoVault: health factor below floor");

        if (postHf < preHf) {
            require(postHf >= reduceOnlyHealthFactor, "LidoVault: health factor declined below comfort band");
        }

        if (minCollateralRatioBps != 0) {
            require(
                ph.ratioGe(postCollateral, postDebt, minCollateralRatioBps, 10_000, 0),
                "LidoVault: collateral ratio below minimum"
            );
        }
    }
}
