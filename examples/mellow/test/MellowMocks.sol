// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMellowOracle, IMellowRiskManager} from "../src/MellowCuratorInterfaces.sol";

/// @notice Minimal ERC20 with a `setBalance` cheat so a single armed transaction can drive any
///         pre/post custody balance, plus a real `transfer` for outflow tests.
contract MockERC20 {
    string public name = "Mellow Deposit Asset";
    string public symbol = "mDA";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    function setBalance(address account, uint256 amount) external {
        totalSupply = totalSupply - balanceOf[account] + amount;
        balanceOf[account] = amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Oracle stand-in for the report-drift guard. `submitReports` is the monitored call; it
///         overwrites the stored report price (and, via the `nextSuspicious` knob, the suspicious
///         flag) so the assertion's pre/post-call reads see exactly the move under test.
contract MockMellowOracle {
    address[] internal assets;
    mapping(address => IMellowOracle.DetailedReport) internal reports;
    bool public nextSuspicious;

    function addAsset(address asset) external {
        assets.push(asset);
    }

    /// @dev Seeds the prior (baseline) report an asset carries before the monitored call.
    function setReport(address asset, uint224 priceD18, bool isSuspicious) external {
        reports[asset] = IMellowOracle.DetailedReport(priceD18, uint32(block.timestamp), isSuspicious);
    }

    function setNextSuspicious(bool suspicious) external {
        nextSuspicious = suspicious;
    }

    function supportedAssets() external view returns (uint256) {
        return assets.length;
    }

    function supportedAssetAt(uint256 index) external view returns (address) {
        return assets[index];
    }

    function getReport(address asset) external view returns (IMellowOracle.DetailedReport memory) {
        return reports[asset];
    }

    /// @dev Records each report exactly as Mellow's Oracle does: the price is stored regardless of
    ///      the suspicious flag, and a suspicious report does not propagate to vault accounting.
    function submitReports(IMellowOracle.Report[] calldata reports_) external {
        for (uint256 i; i < reports_.length; ++i) {
            reports[reports_[i].asset] =
                IMellowOracle.DetailedReport(reports_[i].priceD18, uint32(block.timestamp), nextSuspicious);
        }
    }
}

/// @notice RiskManager stand-in for the balance-correction guard. `modify*Balance` applies the
///         signed delta straight to the tracked share balance (the mock skips the asset→share
///         conversion and the limit check — those are the protocol's own logic, not what the
///         assertion adds), so a test controls the pre-balance and the delta directly.
contract MockMellowRiskManager {
    IMellowRiskManager.State internal vaultStateStored;
    mapping(address => IMellowRiskManager.State) internal subvaultStateStored;

    function setVaultBalance(int256 balance) external {
        vaultStateStored.balance = balance;
    }

    function setSubvaultBalance(address subvault, int256 balance) external {
        subvaultStateStored[subvault].balance = balance;
    }

    function vaultState() external view returns (IMellowRiskManager.State memory) {
        return vaultStateStored;
    }

    function subvaultState(address subvault) external view returns (IMellowRiskManager.State memory) {
        return subvaultStateStored[subvault];
    }

    function modifyVaultBalance(address, int256 delta) external {
        vaultStateStored.balance += delta;
    }

    function modifySubvaultBalance(address subvault, address, int256 delta) external {
        subvaultStateStored[subvault].balance += delta;
    }
}

/// @notice Subvault stand-in for the allocation-health guard. Each helper performs a one-transaction
///         market move by rewriting the supply-receipt balance (the subvault's supplied position)
///         and the underlying liquidity custodied by the receipt, so a test drives the exact
///         pre/post-tx state the assertion reads.
contract MockMellowSubvault {
    /// @dev Grows/sets the supplied position to `newSupplied` and the market's withdrawable
    ///      liquidity to `reserveLiquidity`, mimicking a `supply` routed through `CallModule.call`.
    function allocate(address aToken, address asset, uint256 newSupplied, uint256 reserveLiquidity) external {
        MockERC20(aToken).setBalance(address(this), newSupplied);
        MockERC20(asset).setBalance(aToken, reserveLiquidity);
    }

    /// @dev A transaction that touches the subvault without changing its supplied position.
    function noop() external {}
}
