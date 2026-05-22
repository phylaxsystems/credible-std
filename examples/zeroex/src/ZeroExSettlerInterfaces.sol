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
