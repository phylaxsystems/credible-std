// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal ERC20 surface used by the Aave v4 example assertions.
interface IAaveV4ERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Minimal Hub surface used by the Aave v4 lending examples.
interface IAaveV4Hub {
    struct PremiumDelta {
        int256 sharesDelta;
        int256 offsetRayDelta;
        uint256 restoredPremiumRay;
    }

    struct Asset {
        uint120 liquidity;
        uint120 realizedFees;
        uint8 decimals;
        uint120 addedShares;
        uint120 swept;
        int200 premiumOffsetRay;
        uint120 drawnShares;
        uint120 premiumShares;
        uint16 liquidityFee;
        uint120 drawnIndex;
        uint96 drawnRate;
        uint40 lastUpdateTimestamp;
        address underlying;
        address irStrategy;
        address reinvestmentController;
        address feeReceiver;
        uint200 deficitRay;
    }

    struct SpokeData {
        uint120 drawnShares;
        uint120 premiumShares;
        int200 premiumOffsetRay;
        uint120 addedShares;
        uint40 addCap;
        uint40 drawCap;
        uint24 riskPremiumThreshold;
        bool active;
        bool halted;
        uint200 deficitRay;
    }

    struct SpokeConfig {
        uint40 addCap;
        uint40 drawCap;
        uint24 riskPremiumThreshold;
        bool active;
        bool halted;
    }

    struct AssetConfig {
        address feeReceiver;
        uint16 liquidityFee;
        address irStrategy;
        address reinvestmentController;
    }

    function add(uint256 assetId, uint256 amount) external returns (uint256);
    function remove(uint256 assetId, uint256 amount, address to) external returns (uint256);
    function draw(uint256 assetId, uint256 amount, address to) external returns (uint256);
    function restore(uint256 assetId, uint256 drawnAmount, PremiumDelta calldata premiumDelta)
        external
        returns (uint256);
    function reportDeficit(uint256 assetId, uint256 drawnAmount, PremiumDelta calldata premiumDelta)
        external
        returns (uint256, uint256);
    function refreshPremium(uint256 assetId, PremiumDelta calldata premiumDelta) external;
    function payFeeShares(uint256 assetId, uint256 shares) external;
    function transferShares(uint256 assetId, uint256 shares, address toSpoke) external;
    function mintFeeShares(uint256 assetId) external returns (uint256);
    function eliminateDeficit(uint256 assetId, uint256 amount, address spoke) external returns (uint256, uint256);
    function sweep(uint256 assetId, uint256 amount) external;
    function reclaim(uint256 assetId, uint256 amount) external;
    function updateAssetConfig(uint256 assetId, AssetConfig calldata config, bytes calldata irData) external;
    function addSpoke(uint256 assetId, address spoke, SpokeConfig calldata config) external;
    function updateSpokeConfig(uint256 assetId, address spoke, SpokeConfig calldata config) external;
    function setInterestRateData(uint256 assetId, bytes calldata irData) external;

    function getAsset(uint256 assetId) external view returns (Asset memory);
    function previewRemoveByShares(uint256 assetId, uint256 shares) external view returns (uint256);
    function getAssetDrawnIndex(uint256 assetId) external view returns (uint256);
    function getAddedAssets(uint256 assetId) external view returns (uint256);
    function getAddedShares(uint256 assetId) external view returns (uint256);
    function getSpokeCount(uint256 assetId) external view returns (uint256);
    function getSpokeAddress(uint256 assetId, uint256 index) external view returns (address);
    function getSpoke(uint256 assetId, address spoke) external view returns (SpokeData memory);
    function getSpokeAddedAssets(uint256 assetId, address spoke) external view returns (uint256);
    function getSpokeAddedShares(uint256 assetId, address spoke) external view returns (uint256);
    function getSpokeDrawnShares(uint256 assetId, address spoke) external view returns (uint256);
    function getSpokePremiumData(uint256 assetId, address spoke) external view returns (uint256, int256);
}

/// @notice Minimal Spoke surface used by the Aave v4 lending examples.
interface IAaveV4Spoke {
    struct Reserve {
        address underlying;
        address hub;
        uint16 assetId;
        uint8 decimals;
        uint24 collateralRisk;
        uint8 flags;
        uint32 dynamicConfigKey;
    }

    struct ReserveConfig {
        uint24 collateralRisk;
        bool paused;
        bool frozen;
        bool borrowable;
        bool receiveSharesEnabled;
    }

    struct DynamicReserveConfig {
        uint16 collateralFactor;
        uint32 maxLiquidationBonus;
        uint16 liquidationFee;
    }

    struct UserPosition {
        uint120 drawnShares;
        uint120 premiumShares;
        int200 premiumOffsetRay;
        uint120 suppliedShares;
        uint32 dynamicConfigKey;
    }

    struct UserAccountData {
        uint256 riskPremium;
        uint256 avgCollateralFactor;
        uint256 healthFactor;
        uint256 totalCollateralValue;
        uint256 totalDebtValueRay;
        uint256 activeCollateralCount;
        uint256 borrowCount;
    }

    function supply(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256);
    function withdraw(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256);
    function borrow(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256);
    function repay(uint256 reserveId, uint256 amount, address onBehalfOf) external returns (uint256, uint256);
    function liquidationCall(
        uint256 collateralReserveId,
        uint256 debtReserveId,
        address user,
        uint256 debtToCover,
        bool receiveShares
    ) external;
    function setUsingAsCollateral(uint256 reserveId, bool usingAsCollateral, address onBehalfOf) external;
    function updateUserRiskPremium(address onBehalfOf) external;
    function updateUserDynamicConfig(address onBehalfOf) external;

    function ORACLE() external view returns (address);
    function getReserveCount() external view returns (uint256);
    function getReserve(uint256 reserveId) external view returns (Reserve memory);
    function getDynamicReserveConfig(uint256 reserveId, uint32 dynamicConfigKey)
        external
        view
        returns (DynamicReserveConfig memory);
    function getUserReserveStatus(uint256 reserveId, address user) external view returns (bool, bool);
    function getUserPosition(uint256 reserveId, address user) external view returns (UserPosition memory);
    function getUserAccountData(address user) external view returns (UserAccountData memory);
    function getUserLastRiskPremium(address user) external view returns (uint256);
}

/// @notice Minimal reserve-price oracle surface used by Aave v4 Spokes.
interface IAaveV4Oracle {
    function getReservePrice(uint256 reserveId) external view returns (uint256);
}
