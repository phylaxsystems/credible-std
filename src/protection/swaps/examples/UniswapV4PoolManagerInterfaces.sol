// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IUniswapV4PoolManagerLike
/// @author Phylax Systems
/// @notice Minimal Uniswap v4 PoolManager surface needed by the example assertion bundle.
/// @dev Currency and IHooks are typed `address` here. The canonical Uniswap v4 ABI encodes
///      both as `address`, so the function selectors derived from these signatures match the
///      production PoolManager exactly.
interface IUniswapV4PoolManagerLike {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    function initialize(PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24 tick);

    function modifyLiquidity(PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData)
        external
        returns (int256 callerDelta, int256 feesAccrued);

    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (int256 swapDelta);

    function donate(PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        returns (int256 delta);

    function take(address currency, address to, uint256 amount) external;

    function settle() external payable returns (uint256);

    function sync(address currency) external;

    function mint(address to, uint256 id, uint256 amount) external;

    function burn(address from, uint256 id, uint256 amount) external;

    function updateDynamicLPFee(PoolKey calldata key, uint24 newDynamicLPFee) external;

    function setProtocolFee(PoolKey calldata key, uint24 newProtocolFee) external;

    function setProtocolFeeController(address controller) external;

    function collectProtocolFees(address recipient, address currency, uint256 amount) external returns (uint256);

    function unlock(bytes calldata data) external returns (bytes memory);

    function protocolFeesAccrued(address currency) external view returns (uint256);

    function extsload(bytes32 slot) external view returns (bytes32);

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory);
}
