// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Minimal Balancer V3 types mirrored from `balancer-v3-monorepo` (`pkg/interfaces`).
// Only the surfaces the assertion bundle reads are included; token addresses are plain
// `address` instead of `IERC20`, which is ABI-identical.

enum SwapKind {
    EXACT_IN,
    EXACT_OUT
}

enum Rounding {
    ROUND_UP,
    ROUND_DOWN
}

enum TokenType {
    STANDARD,
    WITH_RATE
}

/// @notice Calldata for `IVaultMain.swap`, mirrored from Balancer's `VaultSwapParams`.
struct VaultSwapParams {
    SwapKind kind;
    address pool;
    address tokenIn;
    address tokenOut;
    uint256 amountGivenRaw;
    uint256 limitRaw;
    bytes userData;
}

/// @notice Per-token registration data, mirrored from Balancer's `TokenInfo`.
struct TokenInfo {
    TokenType tokenType;
    address rateProvider;
    bool paysYieldFees;
}

/// @notice Pool hook wiring, mirrored from Balancer's `HooksConfig`. The swap-scoped assertion
///         reads only the before/after-swap flags: those hooks execute inside the `Vault.swap`
///         call scope and may legitimately reenter the Vault, so pools that enable them cannot
///         be checked with call-boundary snapshots.
struct HooksConfig {
    bool enableHookAdjustedAmounts;
    bool shouldCallBeforeInitialize;
    bool shouldCallAfterInitialize;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool shouldCallBeforeAddLiquidity;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallBeforeRemoveLiquidity;
    bool shouldCallAfterRemoveLiquidity;
    address hooksContract;
}

/// @notice The Vault surface used by the assertions. Getters live on VaultExtension in
///         production but are reachable through the Vault address via its fallback delegation.
interface IBalancerV3VaultLike {
    function swap(VaultSwapParams calldata vaultSwapParams)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);

    function getPoolTokens(address pool) external view returns (address[] memory tokens);

    function getPoolTokenInfo(address pool)
        external
        view
        returns (
            address[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        );

    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory balancesLiveScaled18);

    function getReservesOf(address token) external view returns (uint256 reserveAmount);

    function getAggregateSwapFeeAmount(address pool, address token) external view returns (uint256 swapFeeAmount);

    function getAggregateYieldFeeAmount(address pool, address token) external view returns (uint256 yieldFeeAmount);

    function totalSupply(address token) external view returns (uint256 tokenTotalSupply);

    function isPoolInitialized(address pool) external view returns (bool initialized);

    function getHooksConfig(address pool) external view returns (HooksConfig memory hooksConfig);

    function isPoolInRecoveryMode(address pool) external view returns (bool inRecoveryMode);
}

/// @notice Pool math surface: the Vault trusts these functions, the assertions re-check them.
interface IBalancerV3BasePoolLike {
    function computeInvariant(uint256[] memory balancesLiveScaled18, Rounding rounding)
        external
        view
        returns (uint256 invariant);
}

/// @notice Rate provider surface for WITH_RATE pool tokens.
interface IRateProviderLike {
    function getRate() external view returns (uint256 rate);
}
