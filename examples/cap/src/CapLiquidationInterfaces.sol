// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal Cap `Lender` surface used by the liquidation assertion.
/// @dev The assertion adopter is the `Lender`. A liquidation repays an agent's debt out of the
///      liquidator's funds (`BorrowLogic.repay`) and slashes the agent's restaked delegation
///      collateral to the liquidator in exchange. `debt`, `reservesData` and
///      `maxRestakerRealization` are read across PreCall/PostCall snapshots to check the outcome.
interface ICapLenderLike {
    /// @notice Liquidate an unhealthy agent: repay `amount` of `asset` debt, slash collateral.
    function liquidate(address agent, address asset, uint256 amount, uint256 minLiquidatedValue)
        external
        returns (uint256 liquidatedValue);

    /// @notice Agent's total debt for an asset (debt-token principal + accrued restaker interest).
    function debt(address agent, address asset) external view returns (uint256 totalDebt);

    /// @notice Reserve config for an asset; index 1 is the vault that custodies the backing.
    function reservesData(address asset)
        external
        view
        returns (
            uint256 id,
            address vault,
            address debtToken,
            address interestReceiver,
            uint8 decimals,
            bool paused,
            uint256 minBorrow
        );

    /// @notice Restaker interest the next repay will realize by borrowing from the vault.
    /// @return realized Interest funded from the vault (lowers claimable backing this call).
    /// @return unrealized Interest deferred onto the agent's debt (does not touch the vault).
    function maxRestakerRealization(address agent, address asset)
        external
        view
        returns (uint256 realized, uint256 unrealized);
}

/// @notice Vault custody view: claimable backing for an asset (`totalSupplies - totalBorrows`).
interface ICapVaultBalanceLike {
    function availableBalance(address asset) external view returns (uint256 amount);
}
