// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

import {
    IBalancerV3BasePoolLike,
    IBalancerV3VaultLike,
    IRateProviderLike,
    Rounding,
    TokenInfo
} from "./BalancerV3VaultInterfaces.sol";

/// @title BalancerV3VaultHelpers
/// @author Phylax Systems
/// @notice Fork-aware Balancer V3 Vault state helpers used by the example assertions.
/// @dev Balancer V3 is a singleton: the Vault custodies every pool's tokens, stores every pool's
///      balances and BPT supply, and delegates only the math to the pool contract. Helpers read
///      the watched pool's registration data, raw balances, live balances, reserves, and aggregate
///      protocol fees through the Vault at snapshot forks, and recompute the pool invariant through
///      the pool's own `computeInvariant`.
abstract contract BalancerV3VaultHelpers is Assertion {
    /// @notice Balancer V3 Vault singleton (the assertion adopter).
    address internal immutable VAULT;

    /// @notice Watched pool registered with the Vault.
    address internal immutable POOL;

    /// @notice Allowed downward invariant movement across one swap, in bps, to absorb pool-math
    ///         rounding dust. Zero enforces strict non-decrease.
    uint256 internal immutable INVARIANT_DUST_TOLERANCE_BPS;

    /// @notice Allowed movement of a token's rate-provider rate within one transaction, in bps.
    uint256 internal immutable RATE_DRIFT_TOLERANCE_BPS;

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    struct PoolTokenSnapshot {
        address[] tokens;
        TokenInfo[] tokenInfo;
        uint256[] balancesRaw;
    }

    /// @dev All addresses and thresholds are supplied explicitly; the constructor never reads the
    ///      adopter because the assertion-deploy runtime is isolated from live chain state.
    constructor(address vault_, address pool_, uint256 invariantDustToleranceBps_, uint256 rateDriftToleranceBps_) {
        require(vault_ != address(0), "BalancerV3: zero vault");
        require(pool_ != address(0), "BalancerV3: zero pool");
        require(invariantDustToleranceBps_ < BPS_DENOMINATOR, "BalancerV3: bad invariant tolerance");
        require(rateDriftToleranceBps_ < BPS_DENOMINATOR, "BalancerV3: bad rate tolerance");

        VAULT = vault_;
        POOL = pool_;
        INVARIANT_DUST_TOLERANCE_BPS = invariantDustToleranceBps_;
        RATE_DRIFT_TOLERANCE_BPS = rateDriftToleranceBps_;
    }

    // --- adopter / calldata -------------------------------------------------

    function _requireConfiguredVaultIsAdopter() internal view {
        require(ph.getAssertionAdopter() == VAULT, "BalancerV3: configured vault is not adopter");
    }

    /// @dev Reads the swap legs straight from `swap(VaultSwapParams)` calldata instead of
    ///      abi-decoding the whole struct: the assertion only needs the pool and token addresses,
    ///      and a full dynamic-struct decode costs enough gas to threaten the assertion budget.
    ///      Layout: 4-byte selector, one head word holding the struct offset, then the struct
    ///      fields (`kind`, `pool`, `tokenIn`, `tokenOut`, ...) in order. The head offset is
    ///      bound-checked before it is followed: an offset the Vault's own decoder would reject
    ///      cannot belong to an executed swap, so malformed calldata fails closed here instead of
    ///      reading unrelated assertion memory.
    function _swapArgs(bytes memory input) internal pure returns (address pool_, address tokenIn_, address tokenOut_) {
        require(input.length >= 4 + 32 * 8, "BalancerV3: short swap calldata");

        uint256 structOffset;
        assembly ("memory-safe") {
            structOffset := mload(add(input, 36)) // skip the bytes length word and the 4-byte selector
        }
        // The struct's static area is 7 words; it must fit inside the argument section.
        require(structOffset <= input.length - 4 - 32 * 7, "BalancerV3: bad swap struct offset");

        uint256 poolWord;
        uint256 tokenInWord;
        uint256 tokenOutWord;
        assembly ("memory-safe") {
            let args := add(input, 36)
            let structBase := add(args, structOffset) // head word points at the struct tuple
            poolWord := mload(add(structBase, 32))
            tokenInWord := mload(add(structBase, 64))
            tokenOutWord := mload(add(structBase, 96))
        }

        pool_ = address(uint160(poolWord));
        tokenIn_ = address(uint160(tokenInWord));
        tokenOut_ = address(uint160(tokenOutWord));
    }

    // --- fork reads ---------------------------------------------------------

    function _poolTokenSnapshotAt(PhEvm.ForkId memory fork) internal view returns (PoolTokenSnapshot memory snap) {
        bytes memory ret = _viewAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.getPoolTokenInfo, (POOL)), fork);
        (snap.tokens, snap.tokenInfo, snap.balancesRaw,) =
            abi.decode(ret, (address[], TokenInfo[], uint256[], uint256[]));
    }

    function _liveBalancesAt(PhEvm.ForkId memory fork) internal view returns (uint256[] memory balancesLiveScaled18) {
        bytes memory liveRet = _viewAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.getCurrentLiveBalances, (POOL)), fork);
        return abi.decode(liveRet, (uint256[]));
    }

    /// @dev Recomputes the watched pool's invariant from live balances through the pool's own
    ///      math, rounding down on both sides of a comparison so fee accrual must exceed dust.
    function _invariantOf(uint256[] memory balancesLiveScaled18, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 invariant)
    {
        return _readUintAt(
            POOL,
            abi.encodeCall(IBalancerV3BasePoolLike.computeInvariant, (balancesLiveScaled18, Rounding.ROUND_DOWN)),
            fork
        );
    }

    /// @dev Registration-order indexes of the swap legs, from one lean `getPoolTokens` read.
    ///      Both legs are matched independently so `tokenIn == tokenOut` resolves to one shared
    ///      index instead of reverting: the Vault rejects same-token swaps, so such a trigger can
    ///      only be observed for a call that left no state change, and the direction checks then
    ///      pin that single balance in place rather than falsely blocking the transaction.
    function _tokenIndexesAt(PhEvm.ForkId memory fork, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 indexIn, uint256 indexOut)
    {
        bytes memory ret = _viewAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.getPoolTokens, (POOL)), fork);
        address[] memory tokens = abi.decode(ret, (address[]));

        indexIn = type(uint256).max;
        indexOut = type(uint256).max;
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i] == tokenIn) {
                indexIn = i;
            }
            if (tokens[i] == tokenOut) {
                indexOut = i;
            }
        }
        require(indexIn != type(uint256).max, "BalancerV3: tokenIn not registered in pool");
        require(indexOut != type(uint256).max, "BalancerV3: tokenOut not registered in pool");
    }

    function _bptTotalSupplyAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.totalSupply, (POOL)), fork);
    }

    function _reservesOfAt(address token, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.getReservesOf, (token)), fork);
    }

    function _aggregateFeesAt(address token, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.getAggregateSwapFeeAmount, (POOL, token)), fork)
            + _readUintAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.getAggregateYieldFeeAmount, (POOL, token)), fork);
    }

    function _isPoolInitializedAt(PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(VAULT, abi.encodeCall(IBalancerV3VaultLike.isPoolInitialized, (POOL)), fork);
    }

    function _rateAt(address rateProvider, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(rateProvider, abi.encodeCall(IRateProviderLike.getRate, ()), fork);
    }

    /// @dev Tolerant rate read for baseline forks: a provider that did not exist or did not
    ///      answer at the fork reads as zero instead of reverting. A staticcall to an address
    ///      without code succeeds with empty returndata, so the strict `_rateAt` would revert in
    ///      `abi.decode` and falsely block a transaction that deploys the provider itself (e.g.
    ///      pool registration bundled with provider deployment).
    function _rateOrZeroAt(address rateProvider, PhEvm.ForkId memory fork) internal view returns (uint256) {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(rateProvider, abi.encodeCall(IRateProviderLike.getRate, ()), FORK_VIEW_GAS, fork);
        if (!result.ok || result.data.length < 32) {
            return 0;
        }
        return abi.decode(result.data, (uint256));
    }

    // --- small math ---------------------------------------------------------

    function _bpsOf(uint256 value, uint256 bps) internal pure returns (uint256) {
        return value * bps / BPS_DENOMINATOR;
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
