// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal ERC20 metadata surface used by the Aave v3 Horizon example.
interface IERC20MetadataLike {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

library AaveV3Types {
    struct UserConfigurationMap {
        uint256 data;
    }

    struct ReserveDataLegacy {
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

/// @notice Minimal pool surface matching the local Aave v3 Horizon pool interface.
/// @dev This example was derived against `~/Documents/code/solidity/aave-v3-horizon/`.
interface IAaveV3PoolLike {
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

    function getUserConfiguration(address user) external view returns (AaveV3Types.UserConfigurationMap memory);

    function getReserveData(address asset) external view returns (AaveV3Types.ReserveDataLegacy memory);

    function getReservesList() external view returns (address[] memory);

    function ADDRESSES_PROVIDER() external view returns (address);
}

interface IAaveV3AddressesProviderLike {
    function getPriceOracle() external view returns (address);
}

interface IAaveV3OracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}
