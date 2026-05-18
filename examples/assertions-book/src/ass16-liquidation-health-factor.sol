// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title Lending Protocol Implementation
 * @notice This contract implements a simple lending protocol for testing the LiquidationHealthFactor assertion
 * @dev Simulates health factor calculations and liquidation functionality
 */
contract LendingProtocol {
    // MarketParams contains the market identifier
    struct MarketParams {
        Id id;
    }

    struct Id {
        uint256 marketId;
    }

    // Mapping to store borrower health factors for each market
    mapping(uint256 => mapping(address => uint256)) private _healthFactors;

    // Health factor constants (using same values as in the assertion)
    uint256 constant LIQUIDATION_THRESHOLD = 1e18; // 1.0
    uint256 constant MIN_HEALTH_FACTOR = 1.02e18; // 1.02
    uint256 constant HEALTHY_FACTOR = 2e18; // 2.0 is healthy

    // Minimum amount required for meaningful health factor improvement
    uint256 constant MIN_REPAID_FOR_IMPROVEMENT = 100e18;

    /**
     * @notice Set a user's health factor for testing
     * @param marketParams The market parameters
     * @param borrower The borrower address
     * @param healthFactor_ The health factor value to set
     */
    function setHealthFactor(MarketParams memory marketParams, address borrower, uint256 healthFactor_) external {
        _healthFactors[marketParams.id.marketId][borrower] = healthFactor_;
    }

    /**
     * @notice Performs a liquidation on a borrower's position
     * @param marketParams The market parameters
     * @param borrower The borrower address being liquidated
     * @param seizedAssets Amount of assets seized from the borrower
     * @param repaidShares Amount of debt shares repaid
     * @param data Additional data for the liquidation (not used in this implementation)
     * @return Amount of assets actually seized and debt shares actually repaid
     */
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes memory data
    ) external returns (uint256, uint256) {
        // Calculate new health factor based on repaid amount
        // In a real protocol, this would involve complex calculations
        // Here we use a simplified approach for testing purposes
        uint256 currentFactor = _healthFactors[marketParams.id.marketId][borrower];
        uint256 newFactor = currentFactor;

        // Only improve health factor if repaid amount is significant
        if (repaidShares >= MIN_REPAID_FOR_IMPROVEMENT) {
            // Improve health factor based on repaid shares
            uint256 improvement = (repaidShares * 1e18) / 1000e18;

            // Set the new health factor
            newFactor = currentFactor + improvement;

            // Make sure health factor is at least above MIN_HEALTH_FACTOR if improvement is applied
            if (newFactor < MIN_HEALTH_FACTOR) {
                newFactor = MIN_HEALTH_FACTOR;
            }
        }

        _healthFactors[marketParams.id.marketId][borrower] = newFactor;

        return (seizedAssets, repaidShares);
    }

    /**
     * @notice Checks if a borrower's position is healthy
     * @param marketParams The market parameters
     * @param borrower The borrower address
     * @return Whether the position is healthy (true) or not (false)
     */
    function isHealthy(MarketParams memory marketParams, address borrower) external view returns (bool) {
        return healthFactor(marketParams, borrower) > LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Returns a borrower's health factor
     * @param marketParams The market parameters
     * @param borrower The borrower address
     * @return The current health factor
     */
    function healthFactor(MarketParams memory marketParams, address borrower) public view returns (uint256) {
        return _healthFactors[marketParams.id.marketId][borrower];
    }
}
