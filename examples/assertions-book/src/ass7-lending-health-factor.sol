// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract LendingHealthFactor {
    // Storage for positions
    mapping(uint256 => mapping(address => Position)) public positions;
    mapping(uint256 => MarketParams) private _idToMarketParams;

    struct MarketParams {
        uint256 marketId;
    }

    struct Position {
        uint256 supplyShares;
        uint128 borrowShares;
        uint128 collateral;
    }

    // For testing purposes, we'll make this return true/false based on a simple condition
    bool public isHealthy = true;

    constructor() {
        // Initialize a market
        _idToMarketParams[1] = MarketParams({marketId: 1});
    }

    function idToMarketParams(uint256 id) external view returns (MarketParams memory) {
        return _idToMarketParams[id];
    }

    function position(uint256 marketId, address user) external view returns (Position memory) {
        return positions[marketId][user];
    }

    function _isHealthy(MarketParams memory marketParams, uint256 marketId, address borrower)
        external
        view
        returns (bool)
    {
        return isHealthy;
    }

    // Functions to modify positions
    function supply(uint256 marketId, uint256 amount) external {
        Position storage pos = positions[marketId][msg.sender];
        pos.supplyShares += amount;
    }

    function borrow(uint256 marketId, uint256 amount) external {
        Position storage pos = positions[marketId][msg.sender];
        pos.borrowShares += uint128(amount);
    }

    function withdraw(uint256 marketId, uint256 amount) external {
        Position storage pos = positions[marketId][msg.sender];
        pos.supplyShares -= amount;
    }

    function repay(uint256 marketId, uint256 amount) external {
        Position storage pos = positions[marketId][msg.sender];
        pos.borrowShares -= uint128(amount);
    }

    // Function to set health status for testing
    function setHealthStatus(bool _healthy) external {
        isHealthy = _healthy;
    }
}
