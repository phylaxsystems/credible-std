// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal Denaria perp-pair surface used by the example suite.
/// @dev Derived against `~/Documents/code/solidity/denaria-perp-main/`.
interface IDenariaPerpPairLike {
    function trade(
        bool direction,
        uint256 size,
        uint256 minTradeReturn,
        uint256 initialGuess,
        address frontendAddress,
        uint8 leverage,
        bytes memory unverifiedReport
    ) external returns (uint256);

    function closeAndWithdraw(
        uint256 maxSlippage,
        uint256 maxLiqFee,
        address frontendAddress,
        bytes memory unverifiedReport
    ) external;

    function addLiquidity(
        uint256 liquidityStable,
        uint256 liquidityAsset,
        uint256 maxFeeValue,
        bytes memory unverifiedReport
    ) external;

    function removeLiquidity(
        uint256 liquidityStableToRemove,
        uint256 liquidityAssetToRemove,
        uint256 maxFeeValue,
        bytes memory unverifiedReport
    ) external;

    function realizePnL(bytes calldata unverifiedReport) external returns (uint256, bool);
    function liquidate(address user, uint256 liquidatedPositionSize, bytes memory unverifiedReport) external;
    function getPrice() external view returns (uint256);
    function calcPnL(address user, uint256 price) external view returns (uint256, bool);
    function computeFundingFee(address user) external view returns (uint256, bool);
    function getLpLiquidityBalance(address user) external view returns (uint256, uint256);
    function MMR() external view returns (uint256);
    function maxLpLeverage() external view returns (uint256);
    function globalLiquidityStable() external view returns (uint256);
    function globalLiquidityAsset() external view returns (uint256);
    function insuranceFund() external view returns (uint256);
    function insuranceFundSign() external view returns (bool);

    function userVirtualTraderPosition(address user)
        external
        view
        returns (
            uint256 balanceStable,
            uint256 balanceAsset,
            uint256 debtStable,
            uint256 debtAsset,
            uint256 fundingFee,
            bool fundingFeeSign,
            uint256 initialFundingRate,
            bool initialFundingRateSign
        );

    function liquidityPosition(address user)
        external
        view
        returns (uint256 initialStableShares, uint256 initialAssetShares, uint256 debtStable, uint256 debtAsset);
}

/// @notice Minimal Denaria vault surface used by the example suite.
interface IDenariaVaultLike {
    function removeCollateral(uint256 amount, bytes memory unverifiedReport) external;
    function removeAllCollateral(bytes memory unverifiedReport) external;
    function userCollateral(address user) external view returns (uint256);
}
