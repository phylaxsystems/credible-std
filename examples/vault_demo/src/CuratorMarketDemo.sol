// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mutable price feed used to reproduce price-deviation fault scenarios.
contract VaultDemoOracle {
    uint256 public price;

    constructor(uint256 initialPrice) {
        price = initialPrice;
    }

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}

/// @notice Minimal lending market with utilization and oracle surfaces for curator-allocation demos.
contract VaultDemoMarket {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    VaultDemoOracle public immutable oracle;

    uint256 public totalDeposits;
    uint256 public totalBorrowed;

    constructor(IERC20 asset_, VaultDemoOracle oracle_) {
        asset = asset_;
        oracle = oracle_;
    }

    function deposit(uint256 assets) external {
        asset.safeTransferFrom(msg.sender, address(this), assets);
        totalDeposits += assets;
    }

    function setBorrowed(uint256 borrowed) external {
        totalBorrowed = borrowed;
    }

    function utilizationBps() external view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrowed * 10_000) / totalDeposits;
    }
}

/// @notice Curator-controlled vault facade. The curator is authorized, but assertions can block bad targets.
contract CuratorVaultDemo {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public immutable curator;

    constructor(IERC20 asset_, address curator_) {
        asset = asset_;
        curator = curator_;
    }

    modifier onlyCurator() {
        require(msg.sender == curator, "VaultDemo: not curator");
        _;
    }

    function allocate(address market, uint256 assets) external onlyCurator {
        asset.forceApprove(market, assets);
        VaultDemoMarket(market).deposit(assets);
        asset.forceApprove(market, 0);
    }
}
