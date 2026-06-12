// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice KyberSwap aggregator swap description.
/// @dev Layout is pinned by the verified `MetaAggregationRouterV2.swap` selector
///      `0xe21fd0e9 = swap((address,address,bytes,(address,address,address[],uint256[],
///      address[],uint256[],address,uint256,uint256,uint256,bytes),bytes))`. The fields used by
///      the example assertions are `dstToken`, `dstReceiver`, and `minReturnAmount`.
struct SwapDescriptionV2 {
    address srcToken;
    address dstToken;
    address[] srcReceivers;
    uint256[] srcAmounts;
    address[] feeReceivers;
    uint256[] feeAmounts;
    address dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
}

/// @notice Top-level argument tuple of `MetaAggregationRouterV2.swap` / `swapGeneric`.
struct SwapExecutionParams {
    address callTarget;
    address approveTarget;
    bytes targetData;
    SwapDescriptionV2 desc;
    bytes clientData;
}

/// @notice Public KyberSwap MetaAggregationRouterV2 settlement entry points protected here.
/// @dev All three fund-moving settlement entry points are modeled, each verified against the
///      mainnet `MetaAggregationRouterV2` source (`0x6131B5fae19EA4f9D964eAc0408E4408b66337b5`):
///      - `swap`           selector 0xe21fd0e9 (forces the executor `callBytes` selector);
///      - `swapGeneric`    selector 0x59e50fed (same `SwapExecutionParams` shape as `swap`, but
///        issues a raw `callTarget.call(targetData)` to a whitelisted target);
///      - `swapSimpleMode` selector 0x8af033fb (executor-supplied fast path).
///      `swap` internally dispatches to `swapSimpleMode` when the `_SIMPLE_SWAP` (0x20) flag is
///      set; that path keeps the `swap` selector, so decoding stays driven by the entry selector.
interface IKyberMetaAggregationRouterV2Like {
    function swap(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed);

    function swapGeneric(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed);

    function swapSimpleMode(
        address caller,
        SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 gasUsed);
}

/// @notice Minimal ERC20 allowance surface used for pre-call authorization checks.
interface IERC20AllowanceReaderLike {
    function allowance(address owner, address spender) external view returns (uint256);
}
