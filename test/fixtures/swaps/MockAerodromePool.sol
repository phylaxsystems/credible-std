// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MockAerodromePool
/// @notice Configurable Aerodrome pool mock for credible-std assertion regression tests.
/// @dev Implements only the storage view surface and `swap` mutator that AerodromePoolAssertion
///      reads. Reserves are kept in plain storage and updated on `swap`/`sync` according to a
///      `Mode` flag so failing scenarios can be expressed deterministically.
contract MockAerodromePool is ERC20 {
    enum Mode {
        Honest,
        KDecreasing
    }

    address public immutable token0;
    address public immutable token1;
    address public immutable poolFeesAddress;
    bool public immutable stable;

    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public reserve0CumulativeLast;
    uint256 public reserve1CumulativeLast;
    uint256 public blockTimestampLast;

    Mode public mode;

    /// @dev Aerodrome's pool exposes `metadata()` returning (dec0, dec1, r0, r1, stable, t0, t1).
    constructor(address _token0, address _token1, address _poolFees, bool _stable) ERC20("MockAeroLP", "MA-LP") {
        token0 = _token0;
        token1 = _token1;
        poolFeesAddress = _poolFees;
        stable = _stable;
    }

    function setMode(Mode m) external {
        mode = m;
    }

    function poolFees() external view returns (address) {
        return poolFeesAddress;
    }

    function setReserves(uint256 r0, uint256 r1) external {
        reserve0 = r0;
        reserve1 = r1;
    }

    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1)
    {
        dec0 = 1e18;
        dec1 = 1e18;
        r0 = reserve0;
        r1 = reserve1;
        st = stable;
        t0 = token0;
        t1 = token1;
    }

    function observationLength() external pure returns (uint256) {
        return 0;
    }

    function lastObservation() external pure returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }

    /// @notice Mints LP tokens to `to`. Test fixtures use this to seed totalSupply for invariant
    ///         checks that depend on supply-conservation (`assertClaimFeesPreservesPoolLiquidity`).
    function mintLP(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Seed the pool's actual ERC-20 balances to match the configured reserves so the
    ///         assertion's `reserve == balance` invariant holds before the mutating call.
    function syncBalancesToReserves() external {
        // Test harness funds the pool directly via ERC20Mock.mint — nothing to do here.
    }

    /// @notice Stub Aerodrome swap. Updates the in/out reserves to a target k according to mode.
    /// @dev Uses Uniswap-style swap semantics: caller specifies output amounts; we implicitly take
    ///      input from the pool's token balances. The mock honors the assertion's preconditions:
    ///      `reserve0 == balance0` post-swap when mode == Honest; `K_post < K_pre` when mode ==
    ///      KDecreasing.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata /* data */ ) external {
        require(amount0Out > 0 || amount1Out > 0, "no output");
        require(amount0Out < reserve0 && amount1Out < reserve1, "insufficient liquidity");

        // Read post-swap balances by simulating the input. Tests pre-fund the pool with the
        // correct input so the post-swap balance equals the new reserves.
        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);

        uint256 newReserve0 = IERC20(token0).balanceOf(address(this));
        uint256 newReserve1 = IERC20(token1).balanceOf(address(this));

        if (mode == Mode.KDecreasing) {
            // Force a curve-decreasing post-state: shrink one reserve below its true balance.
            newReserve0 = newReserve0 / 2;
        }

        reserve0 = newReserve0;
        reserve1 = newReserve1;
        blockTimestampLast = block.timestamp;
    }

    /// @notice `sync()` honest behavior — set reserves to current balances. Tests use this to
    ///         exercise `assertReservesMatchBalances` on the honest path.
    function sync() external {
        reserve0 = IERC20(token0).balanceOf(address(this));
        reserve1 = IERC20(token1).balanceOf(address(this));
        blockTimestampLast = block.timestamp;
    }
}
