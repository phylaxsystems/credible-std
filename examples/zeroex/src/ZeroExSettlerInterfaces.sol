// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Minimal 0x Settler slippage tuple used by the public settlement entry points.
struct ZeroExSettlerSlippage {
    address payable recipient;
    address buyToken;
    uint256 minAmountOut;
}

/// @notice Public taker-submitted 0x Settler entry points protected by the example assertions.
interface IZeroExSettlerLike {
    function execute(ZeroExSettlerSlippage calldata slippage, bytes[] calldata actions, bytes32 zidAndAffiliate)
        external
        payable
        returns (bool);

    function executeWithPermit(
        ZeroExSettlerSlippage calldata slippage,
        bytes[] calldata actions,
        bytes32 zidAndAffiliate,
        bytes calldata permitData
    ) external payable returns (bool);
}

/// @notice Public meta-transaction 0x Settler entry point protected by the example assertions.
interface IZeroExSettlerMetaTxnLike {
    function executeMetaTxn(
        ZeroExSettlerSlippage calldata slippage,
        bytes[] calldata actions,
        bytes32 zidAndAffiliate,
        address msgSender,
        bytes calldata sig
    ) external returns (bool);
}

/// @notice Bridge-flavored 0x Settler entry point protected by authorization assertions.
interface IZeroExBridgeSettlerLike {
    function execute(bytes[] calldata actions, bytes32 zidAndAffiliate) external payable returns (bool);
}

/// @notice Minimal ERC20 allowance surface used for pre-call authorization checks.
interface IERC20AllowanceReaderLike {
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @notice Minimal 0x Settler deployer/registry view surface.
interface IZeroExSettlerRegistryLike {
    function ownerOf(uint256 tokenId) external view returns (address);
    function prev(uint128 featureId) external view returns (address);
}

/// @notice Minimal Uniswap V2-style pool surface used for mainnet swap introspection.
interface IZeroExUniV2PoolLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

/// @notice Minimal Uniswap V3-style pool surface used for mainnet swap introspection.
interface IZeroExUniV3PoolLike {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

/// @notice Minimal Uniswap V4 PoolManager surface used for mainnet swap introspection.
interface IZeroExUniV4PoolManagerLike {
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function extsload(bytes32 slot) external view returns (bytes32 value);
    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (int256 balanceDelta);
}
