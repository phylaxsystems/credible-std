// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal Aerodrome pool surface used by the pool assertion example.
interface IAerodromePoolLike {
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function mint(address to) external returns (uint256 liquidity);
    function skim(address to) external;
    function sync() external;

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1);
    function poolFees() external view returns (address);
}

/// @notice Minimal ERC20 balance reader used for fork-aware pool custody checks.
interface IERC20BalanceReaderLike {
    function balanceOf(address account) external view returns (uint256);
}
