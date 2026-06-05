// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IGPv2SettlementLike
/// @author Phylax Systems
/// @notice Minimal CoW Protocol (Gnosis Protocol v2) settlement surface needed by the example
///         assertion bundle.
/// @dev The structs and function signatures mirror `cowprotocol/contracts`
///      (`GPv2Settlement.settle`, `GPv2Settlement.swap`, `GPv2Trade.Data`, `GPv2Interaction.Data`)
///      byte-for-byte, so the selectors derived here match the production settlement contract on
///      mainnet. The bundle only needs the selectors for `settle`/`swap` triggers — it does not
///      decode the full trade tuple — but the exact ABI is kept so the calldata shape and selectors
///      match real on-chain solver settlements. The canonical selector strings are pinned in the
///      bundle's test.
interface IGPv2SettlementLike {
    /// @dev Mirror of `GPv2Trade.Data`. Token addresses are encoded as indices into the
    ///      settlement's `tokens` array; amounts and flags are the signed order terms.
    struct TradeData {
        uint256 sellTokenIndex;
        uint256 buyTokenIndex;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 flags;
        uint256 executedAmount;
        bytes signature;
    }

    /// @dev Mirror of `GPv2Interaction.Data`: an arbitrary call the solver asks the settlement
    ///      contract to make. The fully arbitrary `target`/`value`/`callData` here is exactly the
    ///      power that lets a solver move the settlement contract's own buffers and grant approvals.
    struct InteractionData {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @dev Mirror of Balancer's `IVault.BatchSwapStep`, used only by the `swap` fast-path.
    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    /// @notice Batch settlement entry point. Solver-only on the real contract.
    function settle(
        address[] calldata tokens,
        uint256[] calldata clearingPrices,
        TradeData[] calldata trades,
        InteractionData[][3] calldata interactions
    ) external;

    /// @notice Single-order Balancer fast-path. Solver-only on the real contract.
    function swap(BatchSwapStep[] calldata swaps, address[] calldata tokens, TradeData calldata trade) external;

    /// @notice The vault relayer that holds user approvals. Never a legitimate value recipient.
    function vaultRelayer() external view returns (address);
}

/// @title IERC20BalanceLike
/// @notice Minimal ERC20 balance surface for snapshot reads.
interface IERC20BalanceLike {
    function balanceOf(address account) external view returns (uint256);
}
