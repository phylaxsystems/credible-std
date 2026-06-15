// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal Aave v3-like pool surface used for vault position health reads.
interface IAaveV3PoolLike {
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
}

/// @notice Minimal Aave v3-like oracle surface used to convert base-currency values.
interface IAaveOracleLike {
    function getAssetPrice(address asset) external view returns (uint256 price);
}

/// @notice Minimal Chainlink aggregator surface used for stETH/ETH market-price reads.
interface IChainlinkFeedLike {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Minimal wstETH surface used to read the Lido protocol exchange rate.
interface IWstETHLike {
    function stEthPerToken() external view returns (uint256 rate);
}

/// @notice Generic share/asset rate source surface (`getRate()` returning base per share/unit).
/// @dev Matches Balancer-style rate providers, Veda accountants, and Mellow-style oracles alike.
interface IRateProviderLike {
    function getRate() external view returns (uint256 rate);
}

/// @notice Minimal ERC-20 surface used by supply and NAV reads.
interface IERC20Like {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
