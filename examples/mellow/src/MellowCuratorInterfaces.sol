// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal surface of Mellow flexible-vaults `Oracle` — the contract a privileged reporter
///         calls to reprice the vault. Signatures match `mellow-finance/flexible-vaults`
///         (`src/oracles/Oracle.sol`, `src/interfaces/oracles/IOracle.sol`) exactly so the
///         registered trigger selector lines up with the real call.
/// @dev `submitReports((address,uint224)[])` = 0x8f88cbfb. The reported `priceD18` is the
///      share-pricing number: `shares = assets * priceD18 / 1e18`. A new non-suspicious report
///      propagates straight into vault/queue accounting, so its drift is the blast radius.
interface IMellowOracle {
    /// @notice One asset's price as submitted in a report.
    struct Report {
        address asset;
        uint224 priceD18;
    }

    /// @notice The stored, validated report for an asset.
    struct DetailedReport {
        uint224 priceD18;
        uint32 timestamp;
        bool isSuspicious;
    }

    function submitReports(Report[] calldata reports) external; // 0x8f88cbfb

    function getReport(address asset) external view returns (DetailedReport memory); // 0xa3bdae3e

    function supportedAssets() external view returns (uint256); // 0xa80ce55c

    function supportedAssetAt(uint256 index) external view returns (address); // 0x42c74b19
}

/// @notice Minimal surface of Mellow flexible-vaults `RiskManager` — the curator-power surface that
///         holds approximate (sub)vault share balances and exposes the "trusted balance correction"
///         entrypoints. Matches `src/managers/RiskManager.sol`.
/// @dev `modifyVaultBalance` / `modifySubvaultBalance` adjust internal accounting only (a signed
///      asset-denominated delta is converted to shares and added to the tracked balance). The
///      protocol bounds only the positive direction against the configured limit; negative
///      corrections are unbounded on-chain.
interface IMellowRiskManager {
    /// @notice Tracked approximate share balance and its limit for a vault or subvault.
    struct State {
        int256 balance;
        int256 limit;
    }

    function modifyVaultBalance(address asset, int256 delta) external; // 0x82dcf074

    function modifySubvaultBalance(address subvault, address asset, int256 delta) external; // 0xfea34d98

    function vaultState() external view returns (State memory); // 0x2728f333

    function subvaultState(address subvault) external view returns (State memory); // 0x36f1409f
}
