// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IAerodromePoolLike
/// @author Phylax Systems
/// @notice Minimal Aerodrome pool surface needed by the example assertion bundle.
interface IAerodromePoolLike {
    struct Observation {
        uint256 timestamp;
        uint256 reserve0Cumulative;
        uint256 reserve1Cumulative;
    }

    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function poolFees() external view returns (address);
    function totalSupply() external view returns (uint256);
    function reserve0() external view returns (uint256);
    function reserve1() external view returns (uint256);
    function blockTimestampLast() external view returns (uint256);
    function reserve0CumulativeLast() external view returns (uint256);
    function reserve1CumulativeLast() external view returns (uint256);
    function observationLength() external view returns (uint256);
    function lastObservation() external view returns (Observation memory);

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1);

    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
