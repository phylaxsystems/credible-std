// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ICapGateVaultLike {
    function burn(address asset, uint256 amountIn, uint256 minAmountOut, address receiver, uint256 deadline)
        external
        returns (uint256 amountOut);
    function redeem(uint256 amountIn, uint256[] calldata minAmountsOut, address receiver, uint256 deadline)
        external
        returns (uint256[] memory amountsOut);
    function borrow(address asset, uint256 amount, address receiver) external;
}

interface ICapGateFractionalReserveLike {
    function investAll(address asset) external;
    function divestAll(address asset) external;
    function loaned(address asset) external view returns (uint256 loanedAmount);
}

interface IERC20BalanceReaderLike {
    function balanceOf(address account) external view returns (uint256 balance);
}
