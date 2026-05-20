// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal ERC20 metadata surface used by the Aave v3-like lending examples.
interface IERC20MetadataLike {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @notice Minimal reserve and user structs shared by Aave v3-like pool forks.
library AaveV3LikeTypes {
    struct UserConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        uint256 configurationData;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}

/// @notice Minimal pool surface shared by Aave v3-compatible lending markets.
interface IAaveV3LikePool {
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    function setUserEMode(uint8 categoryId) external;

    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external;

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function getUserConfiguration(address user) external view returns (AaveV3LikeTypes.UserConfigurationMap memory);

    function getReserveData(address asset) external view returns (AaveV3LikeTypes.ReserveData memory);

    function getReservesList() external view returns (address[] memory);

    function ADDRESSES_PROVIDER() external view returns (address);
}

interface IAaveV3LikeAddressesProvider {
    function getPriceOracle() external view returns (address);
}

interface IAaveV3LikeOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}
