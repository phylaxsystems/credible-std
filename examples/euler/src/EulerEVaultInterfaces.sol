// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IEulerEVaultLike
/// @author Phylax Systems
/// @notice Minimal Euler Vault Kit EVault surface needed by the example assertions.
/// @dev Selectors match the EVK share-token, ERC-4626, borrowing, and liquidation modules.
interface IEulerEVaultLike {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transferFromMax(address from, address to) external returns (bool);

    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function deposit(uint256 amount, address receiver) external returns (uint256);
    function mint(uint256 amount, address receiver) external returns (uint256);
    function withdraw(uint256 amount, address receiver, address owner) external returns (uint256);
    function redeem(uint256 amount, address receiver, address owner) external returns (uint256);
    function skim(uint256 amount, address receiver) external returns (uint256);

    function cash() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function debtOf(address account) external view returns (uint256);
    function debtOfExact(address account) external view returns (uint256);
    function dToken() external view returns (address);
    function borrow(uint256 amount, address receiver) external returns (uint256);
    function repay(uint256 amount, address receiver) external returns (uint256);
    function repayWithShares(uint256 amount, address receiver) external returns (uint256 shares, uint256 debt);
    function pullDebt(uint256 amount, address from) external;
    function flashLoan(uint256 amount, bytes calldata data) external;
    function touch() external;

    function checkLiquidation(address liquidator, address violator, address collateral)
        external
        view
        returns (uint256 maxRepay, uint256 maxYield);
    function liquidate(address violator, address collateral, uint256 repayAssets, uint256 minYieldBalance) external;
}
