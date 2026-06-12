// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal Cap surface used by the mint-backing assertion.
/// @dev In Cap, `CapToken` is simultaneously the cUSD ERC20, the `Vault`
///      (mint/burn/redeem + reserve accounting) and the `FractionalReserve`.
///      The assertion adopter is therefore the CapToken itself.
interface ICapVaultLike {
    /// @notice cUSD minted against a single backing asset (asset in, cUSD out).
    function mint(address asset, uint256 amountIn, uint256 minAmountOut, address receiver, uint256 deadline)
        external
        returns (uint256 amountOut);

    /// @notice cUSD burned for a single backing asset (cUSD in, asset out).
    function burn(address asset, uint256 amountIn, uint256 minAmountOut, address receiver, uint256 deadline)
        external
        returns (uint256 amountOut);

    /// @notice cUSD burned for a proportional basket of all backing assets.
    function redeem(uint256 amountIn, uint256[] calldata minAmountsOut, address receiver, uint256 deadline)
        external
        returns (uint256[] memory amountsOut);

    /// @notice Total backing supplied for an asset. Conserved across borrow and
    ///         fractional-reserve investment; only mint/burn/redeem move it.
    function totalSupplies(address asset) external view returns (uint256 totalSupply);

    /// @notice Asset units currently borrowed out to agents through the Lender.
    function totalBorrows(address asset) external view returns (uint256 totalBorrow);
}

/// @notice Fractional-reserve view used to reconstruct idle-vs-accounted custody.
interface ICapFractionalReserveLike {
    /// @notice Asset units currently deployed into the fractional-reserve yield vault.
    function loaned(address asset) external view returns (uint256 loanedAmount);
}

/// @notice Cap price oracle. Prices are USD fixed to 8 decimals (Chainlink-style).
interface ICapPriceOracleLike {
    function getPrice(address asset) external view returns (uint256 price, uint256 lastUpdated);
}

/// @notice ERC20 metadata reads used for supply, custody, and decimal normalization.
interface IERC20Like {
    function totalSupply() external view returns (uint256 supply);
    function balanceOf(address account) external view returns (uint256 balance);
    function decimals() external view returns (uint8 dec);
}
