// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AaveV3LikeTypes, IAaveV3LikeOracle, IAaveV3LikePool} from "./AaveV3LikeInterfaces.sol";

/// @title SparkLendOraclePriceGuardAssertion
/// @author Phylax Systems
/// @notice Guards SparkLend risk-increasing calls against synthetic-oracle drift.
/// @dev The assertion compares SparkLend's AaveOracle price with a hypothetical
///      Credible Layer off-chain `marketPrice` reference. It is intentionally standalone
///      so it can be mounted next to
///      `SparkLendV1OperationSafetyAssertion` without changing that bundle.
///
///      The guard is designed for wrapped or rate-bearing assets where the protocol
///      oracle reports an underlying peg or exchange rate while the reserve itself
///      can trade at a discount. When the market price is outside tolerance, risky
///      calls revert while unmonitored repay paths remain available.
contract SparkLendOraclePriceGuardAssertion is Assertion {
    uint256 internal constant PRICE_SCALE = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant CALL_LOOKUP_LIMIT = 16;

    struct WatchEntry {
        address asset;
        address denomAsset;
        uint256 toleranceBps;
    }

    error SparkLendOraclePriceDeviation(
        address asset, address denomAsset, uint256 reportedInDenom, uint256 market, uint256 toleranceBps
    );

    error SparkLendOraclePriceGuardInvalidEntry(address asset, uint256 toleranceBps);
    error SparkLendOraclePriceGuardUnknownTrigger(bytes4 selector);
    error SparkLendOraclePriceGuardTriggerCallNotFound(bytes4 selector, uint256 callStart);

    address public immutable pool;
    address public immutable oracle;
    address public immutable baseCurrency;
    uint256 public immutable baseCurrencyUnit;

    WatchEntry[] internal watchEntries;

    /// @param pool_ SparkLend pool whose risk-increasing selectors are monitored.
    /// @param oracle_ AaveOracle used by the pool to report asset prices.
    /// @param watchEntries_ Per-asset market-pair and tolerance configuration.
    constructor(address pool_, address oracle_, WatchEntry[] memory watchEntries_) {
        require(pool_ != address(0), "SparkLendOracle: zero pool");
        require(oracle_ != address(0), "SparkLendOracle: zero oracle");

        pool = pool_;
        oracle = oracle_;
        baseCurrency = IAaveV3LikeOracle(oracle_).BASE_CURRENCY();
        baseCurrencyUnit = IAaveV3LikeOracle(oracle_).BASE_CURRENCY_UNIT();
        require(baseCurrencyUnit != 0, "SparkLendOracle: zero base unit");

        for (uint256 i; i < watchEntries_.length; ++i) {
            if (watchEntries_[i].asset == address(0) || watchEntries_[i].toleranceBps == 0) {
                revert SparkLendOraclePriceGuardInvalidEntry(watchEntries_[i].asset, watchEntries_[i].toleranceBps);
            }

            watchEntries.push(watchEntries_[i]);
        }
    }

    /// @notice Registers the SparkLend selectors that consume oracle prices on risky paths.
    /// @dev Supply and repay are deliberately not registered. This leaves debt repayment
    ///      open when a watched wrapped asset depegs and risky calls enter reduce-only mode.
    function triggers() external view override {
        registerFnCallTrigger(this.assertOraclePricesTrackMarket.selector, IAaveV3LikePool.borrow.selector);
        registerFnCallTrigger(this.assertOraclePricesTrackMarket.selector, IAaveV3LikePool.withdraw.selector);
        registerFnCallTrigger(this.assertOraclePricesTrackMarket.selector, IAaveV3LikePool.liquidationCall.selector);
        registerFnCallTrigger(this.assertOraclePricesTrackMarket.selector, IAaveV3LikePool.setUserEMode.selector);
    }

    /// @notice Checks touched watched assets against off-chain market reference prices.
    /// @dev Uses the matched call's pre-call fork for both AaveOracle reads and
    ///      user-configuration reads. Borrow, withdraw, and eMode calls also inspect
    ///      the user's active watched collateral/debt bits because Aave health-factor
    ///      calculations consume account-wide oracle prices, not only the calldata asset.
    function assertOraclePricesTrackMarket() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);
        PhEvm.ForkId memory fork = _preCall(ctx.callStart);

        if (ctx.selector == IAaveV3LikePool.borrow.selector) {
            (address asset,,,, address onBehalfOf) =
                abi.decode(_stripSelector(input), (address, uint256, uint256, uint16, address));
            _checkIfWatched(asset, fork);
            _checkWatchedAccountPositions(onBehalfOf, fork, asset);
            return;
        }

        if (ctx.selector == IAaveV3LikePool.withdraw.selector) {
            (address asset,,) = abi.decode(_stripSelector(input), (address, uint256, address));
            address caller = _triggerCaller(ctx);
            _checkIfWatched(asset, fork);
            _checkWatchedAccountPositions(caller, fork, asset);
            return;
        }

        if (ctx.selector == IAaveV3LikePool.liquidationCall.selector) {
            (address collateralAsset, address debtAsset,,,) =
                abi.decode(_stripSelector(input), (address, address, address, uint256, bool));
            _checkIfWatched(collateralAsset, fork);
            _checkIfWatched(debtAsset, fork);
            return;
        }

        if (ctx.selector == IAaveV3LikePool.setUserEMode.selector) {
            _checkWatchedAccountPositions(_triggerCaller(ctx), fork, address(0));
            return;
        }

        revert SparkLendOraclePriceGuardUnknownTrigger(ctx.selector);
    }

    /// @notice Returns the configured number of watched assets.
    function watchEntryCount() external view returns (uint256) {
        return watchEntries.length;
    }

    /// @notice Returns one watched asset entry by index.
    function watchEntry(uint256 index) external view returns (WatchEntry memory) {
        return watchEntries[index];
    }

    function _checkIfWatched(address asset, PhEvm.ForkId memory fork) internal view {
        (bool found, WatchEntry memory entry) = _findWatchEntry(asset);
        if (!found) {
            return;
        }

        _checkEntry(entry, fork);
    }

    function _checkWatchedAccountPositions(address account, PhEvm.ForkId memory fork, address alreadyChecked)
        internal
        view
    {
        if (account == address(0)) {
            return;
        }

        AaveV3LikeTypes.UserConfigurationMap memory userConfig = abi.decode(
            _viewAt(pool, abi.encodeCall(IAaveV3LikePool.getUserConfiguration, (account)), fork),
            (AaveV3LikeTypes.UserConfigurationMap)
        );

        for (uint256 i; i < watchEntries.length; ++i) {
            WatchEntry memory entry = watchEntries[i];
            if (entry.asset == alreadyChecked) {
                continue;
            }

            (bool initialized, AaveV3LikeTypes.ReserveData memory reserveData) = _tryGetReserveData(entry.asset, fork);
            if (initialized && _isUsingReserve(userConfig.data, reserveData.id)) {
                _checkEntry(entry, fork);
            }
        }
    }

    function _checkEntry(WatchEntry memory entry, PhEvm.ForkId memory fork) internal view {
        uint256 reportedInDenom = _reportedPriceInDenom(entry.asset, entry.denomAsset, fork);
        uint256 market = ph.marketPrice(entry.asset, entry.denomAsset);
        require(market != 0, "SparkLendOracle: zero market price");

        bool aboveLowerBound = ph.ratioGe(reportedInDenom, 1, market, 1, entry.toleranceBps);
        bool belowUpperBound = ph.ratioGe(market, BPS, reportedInDenom, BPS + entry.toleranceBps, 0);

        if (!aboveLowerBound || !belowUpperBound) {
            revert SparkLendOraclePriceDeviation(
                entry.asset, entry.denomAsset, reportedInDenom, market, entry.toleranceBps
            );
        }
    }

    function _reportedPriceInDenom(address asset, address denomAsset, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        uint256 reportedBase = _oraclePriceAt(asset, fork);
        require(reportedBase != 0, "SparkLendOracle: zero reported price");

        if (denomAsset == address(0)) {
            return ph.mulDivDown(reportedBase, PRICE_SCALE, baseCurrencyUnit);
        }

        uint256 denomBase = _oraclePriceAt(denomAsset, fork);
        require(denomBase != 0, "SparkLendOracle: zero denom price");

        return ph.mulDivDown(reportedBase, PRICE_SCALE, denomBase);
    }

    function _oraclePriceAt(address asset, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(oracle, abi.encodeCall(IAaveV3LikeOracle.getAssetPrice, (asset)), fork);
    }

    function _triggerCaller(PhEvm.TriggerContext memory ctx) internal view returns (address) {
        PhEvm.TriggerCall[] memory calls = _matchingCalls(pool, ctx.selector, CALL_LOOKUP_LIMIT);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].callId == ctx.callStart) {
                return calls[i].caller;
            }
        }

        revert SparkLendOraclePriceGuardTriggerCallNotFound(ctx.selector, ctx.callStart);
    }

    function _tryGetReserveData(address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool initialized, AaveV3LikeTypes.ReserveData memory reserveData)
    {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(pool, abi.encodeCall(IAaveV3LikePool.getReserveData, (asset)), FORK_VIEW_GAS, fork);

        if (!result.ok || result.data.length == 0) {
            return (false, reserveData);
        }

        reserveData = abi.decode(result.data, (AaveV3LikeTypes.ReserveData));
        initialized = reserveData.aTokenAddress != address(0);
    }

    function _findWatchEntry(address asset) internal view returns (bool found, WatchEntry memory entry) {
        for (uint256 i; i < watchEntries.length; ++i) {
            if (watchEntries[i].asset == asset) {
                return (true, watchEntries[i]);
            }
        }
    }

    function _isUsingReserve(uint256 userConfigData, uint256 reserveId) internal pure returns (bool) {
        return ((userConfigData >> (reserveId * 2)) & 3) != 0;
    }

    /// @notice Strip the 4-byte selector from raw call input bytes.
    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "SparkLendOracle: input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}

/// @title SparkLendOraclePriceGuardMainnetConfig
/// @notice Canonical starting watch list for SparkLend mainnet synthetic-oracle markets.
/// @dev Operators should tune tolerances from backtests and governance risk appetite.
///      DAI, USDC, and USDS are intentionally omitted by default; they can be added
///      if an adopter wants to spend gas on those lower-signal fixed-price reserves.
library SparkLendOraclePriceGuardMainnetConfig {
    address internal constant USD = address(0);

    address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant LBTC = 0x8236a87084f8B84306f72007F36F2618A5634494;
    address internal constant TBTC = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant EZETH = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
    address internal constant RSETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    address internal constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address internal constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address internal constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function watchList() internal pure returns (SparkLendOraclePriceGuardAssertion.WatchEntry[] memory entries) {
        entries = new SparkLendOraclePriceGuardAssertion.WatchEntry[](13);

        entries[0] = SparkLendOraclePriceGuardAssertion.WatchEntry(CBBTC, WBTC, 75);
        entries[1] = SparkLendOraclePriceGuardAssertion.WatchEntry(LBTC, WBTC, 75);
        entries[2] = SparkLendOraclePriceGuardAssertion.WatchEntry(TBTC, WBTC, 75);
        entries[3] = SparkLendOraclePriceGuardAssertion.WatchEntry(WBTC, USD, 75);

        entries[4] = SparkLendOraclePriceGuardAssertion.WatchEntry(WEETH, WETH, 125);
        entries[5] = SparkLendOraclePriceGuardAssertion.WatchEntry(EZETH, WETH, 125);
        entries[6] = SparkLendOraclePriceGuardAssertion.WatchEntry(RSETH, WETH, 125);

        entries[7] = SparkLendOraclePriceGuardAssertion.WatchEntry(WSTETH, WETH, 50);
        entries[8] = SparkLendOraclePriceGuardAssertion.WatchEntry(RETH, WETH, 50);

        entries[9] = SparkLendOraclePriceGuardAssertion.WatchEntry(SDAI, DAI, 50);
        entries[10] = SparkLendOraclePriceGuardAssertion.WatchEntry(SUSDS, USDS, 50);
        entries[11] = SparkLendOraclePriceGuardAssertion.WatchEntry(SUSDE, USD, 75);
        entries[12] = SparkLendOraclePriceGuardAssertion.WatchEntry(USDT, USD, 75);
    }
}
