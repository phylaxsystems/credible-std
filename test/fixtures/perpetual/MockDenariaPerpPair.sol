// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IDenariaPerpPairLike} from "../../../src/protection/perpetual/examples/DenariaInterfaces.sol";

/// @title MockDenariaPerpPair
/// @notice Minimal mock implementing the Denaria PerpPair interface surface used by the suite.
/// @dev Provides configurable state and emits the events the assertion suite decodes.
///      Uses tiny, deterministic numbers — not a faithful Denaria replica.
contract MockDenariaPerpPair is IDenariaPerpPairLike {
    // ---------------------------------------------------------------
    //  Events (must match the topic0 hashes in DenariaHelpers)
    // ---------------------------------------------------------------

    event ExecutedTrade(
        address indexed user,
        bool direction,
        uint256 tradeSize,
        uint256 tradeReturn,
        uint256 currentPrice,
        uint256 leverage
    );

    event LiquidatedUser(
        address indexed user,
        address liquidator,
        uint256 fraction,
        uint256 liquidationFee,
        uint256 positionSize,
        uint256 currentPrice,
        int256 deltaPnl,
        bool liquidationDirection
    );

    event LiquidityMoved(
        address indexed user,
        uint256 liquidityStable,
        uint256 liquidityAsset,
        uint256 stableShares,
        uint256 assetShares,
        uint256 feeValue,
        bool added
    );

    // ---------------------------------------------------------------
    //  Configurable state
    // ---------------------------------------------------------------

    uint256 public price;
    uint256 public mmr;
    uint256 public maxLpLev;
    uint256 public globalLiqStable;
    uint256 public globalLiqAsset;
    uint256 public insFund;
    bool public insFundSign;

    struct VirtualPosition {
        uint256 balanceStable;
        uint256 balanceAsset;
        uint256 debtStable;
        uint256 debtAsset;
        uint256 fundingFee;
        bool fundingFeeSign;
        uint256 initialFundingRate;
        bool initialFundingRateSign;
    }

    struct LpPosition {
        uint256 initialStableShares;
        uint256 initialAssetShares;
        uint256 debtStable;
        uint256 debtAsset;
    }

    struct LpBalance {
        uint256 stableBalance;
        uint256 assetBalance;
    }

    struct PnlResult {
        uint256 magnitude;
        bool sign;
    }

    struct FundingResult {
        uint256 fee;
        bool sign;
    }

    mapping(address => VirtualPosition) public positions;
    mapping(address => LpPosition) public lpPositions;
    mapping(address => LpBalance) public lpBalances;
    mapping(address => PnlResult) public pnlResults;
    mapping(address => FundingResult) public fundingResults;

    // ---------------------------------------------------------------
    //  Setup helpers (test-only)
    // ---------------------------------------------------------------

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function setMMR(uint256 mmr_) external {
        mmr = mmr_;
    }

    function setMaxLpLeverage(uint256 maxLpLev_) external {
        maxLpLev = maxLpLev_;
    }

    function setGlobalLiquidity(uint256 stable_, uint256 asset_) external {
        globalLiqStable = stable_;
        globalLiqAsset = asset_;
    }

    function setInsuranceFund(uint256 amount_, bool sign_) external {
        insFund = amount_;
        insFundSign = sign_;
    }

    function setVirtualPosition(
        address user,
        uint256 balStable,
        uint256 balAsset,
        uint256 debtStable,
        uint256 debtAsset,
        uint256 fundingFee,
        bool fundingFeeSign
    ) external {
        positions[user] = VirtualPosition(
            balStable, balAsset, debtStable, debtAsset, fundingFee, fundingFeeSign, 0, true
        );
    }

    function setLpPosition(
        address user,
        uint256 initStableShares,
        uint256 initAssetShares,
        uint256 debtStable,
        uint256 debtAsset
    ) external {
        lpPositions[user] = LpPosition(initStableShares, initAssetShares, debtStable, debtAsset);
    }

    function setLpBalance(address user, uint256 stableBalance, uint256 assetBalance) external {
        lpBalances[user] = LpBalance(stableBalance, assetBalance);
    }

    function setPnlResult(address user, uint256 magnitude, bool sign) external {
        pnlResults[user] = PnlResult(magnitude, sign);
    }

    function setFundingResult(address user, uint256 fee, bool sign) external {
        fundingResults[user] = FundingResult(fee, sign);
    }

    // ---------------------------------------------------------------
    //  IDenariaPerpPairLike view functions
    // ---------------------------------------------------------------

    function getPrice() external view override returns (uint256) {
        return price;
    }

    function MMR() external view override returns (uint256) {
        return mmr;
    }

    function maxLpLeverage() external view override returns (uint256) {
        return maxLpLev;
    }

    function globalLiquidityStable() external view override returns (uint256) {
        return globalLiqStable;
    }

    function globalLiquidityAsset() external view override returns (uint256) {
        return globalLiqAsset;
    }

    function insuranceFund() external view override returns (uint256) {
        return insFund;
    }

    function insuranceFundSign() external view override returns (bool) {
        return insFundSign;
    }

    function userVirtualTraderPosition(address user)
        external
        view
        override
        returns (uint256, uint256, uint256, uint256, uint256, bool, uint256, bool)
    {
        VirtualPosition memory p = positions[user];
        return (
            p.balanceStable,
            p.balanceAsset,
            p.debtStable,
            p.debtAsset,
            p.fundingFee,
            p.fundingFeeSign,
            p.initialFundingRate,
            p.initialFundingRateSign
        );
    }

    function liquidityPosition(address user) external view override returns (uint256, uint256, uint256, uint256) {
        LpPosition memory lp = lpPositions[user];
        return (lp.initialStableShares, lp.initialAssetShares, lp.debtStable, lp.debtAsset);
    }

    function getLpLiquidityBalance(address user) external view override returns (uint256, uint256) {
        LpBalance memory lb = lpBalances[user];
        return (lb.stableBalance, lb.assetBalance);
    }

    function calcPnL(address user, uint256) external view override returns (uint256, bool) {
        PnlResult memory r = pnlResults[user];
        return (r.magnitude, r.sign);
    }

    function computeFundingFee(address user) external view override returns (uint256, bool) {
        FundingResult memory f = fundingResults[user];
        return (f.fee, f.sign);
    }

    // ---------------------------------------------------------------
    //  IDenariaPerpPairLike mutative functions (minimal stubs)
    // ---------------------------------------------------------------

    function trade(bool direction, uint256 size, uint256, uint256, address, uint8 leverage, bytes memory)
        external
        override
        returns (uint256)
    {
        uint256 tradeReturn = size;
        emit ExecutedTrade(msg.sender, direction, size, tradeReturn, price, leverage);
        return tradeReturn;
    }

    function closeAndWithdraw(uint256, uint256, address, bytes memory) external override {
        VirtualPosition memory p = positions[msg.sender];
        if (p.balanceAsset > 0 || p.debtAsset > 0) {
            uint256 tradeSize =
                p.balanceAsset > p.debtAsset ? p.balanceAsset - p.debtAsset : p.debtAsset - p.balanceAsset;
            bool direction = p.debtAsset > p.balanceAsset;
            emit ExecutedTrade(msg.sender, direction, tradeSize, tradeSize, price, 1);
        }
    }

    function addLiquidity(uint256, uint256, uint256, bytes memory) external override {
        emit LiquidityMoved(msg.sender, 0, 0, 0, 0, 0, true);
    }

    function removeLiquidity(uint256 liqStable, uint256 liqAsset, uint256, bytes memory) external override {
        emit LiquidityMoved(msg.sender, liqStable, liqAsset, 0, 0, 0, false);
    }

    function realizePnL(bytes calldata) external override returns (uint256, bool) {
        PnlResult memory r = pnlResults[msg.sender];
        return (r.magnitude, r.sign);
    }

    function liquidate(address user, uint256 liquidatedPositionSize, bytes memory) external override {
        emit LiquidatedUser(user, msg.sender, 1e6, 0, liquidatedPositionSize, price, 0, true);
    }
}
