// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

import {
    ZeroExSettlerMainnetSwapIntrospectionCodec,
    ZeroExSettlerV2Action,
    ZeroExSettlerV2Snapshot,
    ZeroExSettlerV3Action,
    ZeroExSettlerV3Hop,
    ZeroExSettlerV4Fill
} from "./ZeroExSettlerMainnetSwapIntrospectionCodec.sol";
import {IZeroExUniV2PoolLike, IZeroExUniV3PoolLike, IZeroExUniV4PoolManagerLike} from "./ZeroExSettlerInterfaces.sol";
import {ZeroExSettlerHelpers} from "./ZeroExSettlerHelpers.sol";

struct ZeroExSettlerSwapIntrospectionState {
    bytes32[] seenLegs;
    PhEvm.Log[] v4SwapLogs;
    uint256 seenCount;
    uint256 nextV4SwapLogIndex;
}

/// @title ZeroExSettlerMainnetSwapIntrospectionHelpers
/// @author Phylax Systems
/// @notice Mainnet 0x Settler action decoding and venue-specific swap checks.
abstract contract ZeroExSettlerMainnetSwapIntrospectionHelpers is ZeroExSettlerHelpers {
    using ZeroExSettlerMainnetSwapIntrospectionCodec for bytes;

    uint256 internal constant BASIS = 10_000;
    uint256 internal constant Q96 = 2 ** 96;
    uint256 internal constant MAX_ACTIONS = 32;
    uint256 internal constant MAX_TRACKED_SWAP_LEGS = 128;
    bytes32 internal constant UNI_V4_POOLS_SLOT = bytes32(uint256(6));

    address internal constant UNI_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant PANCAKE_V3_FACTORY = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;
    address internal constant SUSHI_V3_MAINNET_FACTORY = 0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F;
    address internal constant MAINNET_UNI_V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    bytes32 internal constant UNI_V3_INIT_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
    bytes32 internal constant PANCAKE_V3_INIT_HASH = 0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;

    bytes4 internal constant V4_EXTSLOAD_SELECTOR = IZeroExUniV4PoolManagerLike.extsload.selector;
    bytes32 internal constant V4_SWAP_SIG =
        keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    uint8 internal constant UNI_V3_FORK_ID = 0;
    uint8 internal constant PANCAKE_V3_FORK_ID = 1;
    uint8 internal constant SUSHI_V3_FORK_ID = 2;

    uint256 internal immutable MAX_PRICE_IMPACT_BPS;

    constructor(address settler_, address registry_, uint128 featureId_, uint256 maxPriceImpactBps_)
        ZeroExSettlerHelpers(settler_, registry_, featureId_)
    {
        require(maxPriceImpactBps_ < BASIS, "0xSettler: invalid price impact bps");
        MAX_PRICE_IMPACT_BPS = maxPriceImpactBps_;
    }

    function _assertMainnetActionsWithinPriceImpact(uint256 callStart) internal view {
        bytes memory callInput = ph.callinputAt(callStart);
        uint256 actionsHead = callInput.actionsArrayHead();
        uint256 actionCount = callInput.actionsLength(actionsHead);
        require(actionCount <= MAX_ACTIONS, "0xSettler: too many actions");

        ZeroExSettlerSwapIntrospectionState memory state = ZeroExSettlerSwapIntrospectionState({
            seenLegs: new bytes32[](MAX_TRACKED_SWAP_LEGS),
            v4SwapLogs: _uniV4SwapLogsForCall(callStart),
            seenCount: 0,
            nextV4SwapLogIndex: 0
        });

        for (uint256 i; i < actionCount; ++i) {
            (uint256 actionStart, uint256 actionLength) = callInput.actionBounds(actionsHead, i);
            _assertMainnetActionWithinPriceImpact(callInput, actionStart, actionLength, state, callStart);
        }
    }

    function _assertMainnetActionWithinPriceImpact(
        bytes memory callInput,
        uint256 actionStart,
        uint256 actionLength,
        ZeroExSettlerSwapIntrospectionState memory state,
        uint256 callStart
    ) internal view {
        bytes4 selector = callInput.selectorAt(actionStart, actionLength);
        if (ZeroExSettlerMainnetSwapIntrospectionCodec.isUniV2Action(selector)) {
            ZeroExSettlerV2Action memory decoded = callInput.copySlice(actionStart, actionLength).decodeUniV2Action();
            state.seenCount = _trackUniV2LegKey(state.seenLegs, state.seenCount, decoded);
            _assertUniV2Action(decoded, callStart);
        } else if (ZeroExSettlerMainnetSwapIntrospectionCodec.isUniV3Action(selector)) {
            ZeroExSettlerV3Action memory decoded = callInput.copySlice(actionStart, actionLength).decodeUniV3Action();
            state.seenCount = _trackUniV3LegKeys(state.seenLegs, state.seenCount, decoded);
            _assertUniV3Action(decoded, callStart);
        } else if (ZeroExSettlerMainnetSwapIntrospectionCodec.isUniV3VipAction(selector)) {
            ZeroExSettlerV3Action memory decoded = callInput.copySlice(actionStart, actionLength).decodeUniV3VipAction();
            state.seenCount = _trackUniV3LegKeys(state.seenLegs, state.seenCount, decoded);
            _assertUniV3Action(decoded, callStart);
        } else if (ZeroExSettlerMainnetSwapIntrospectionCodec.isUniV4Action(selector)) {
            ZeroExSettlerV4Fill[] memory fills = callInput.decodeUniV4FillsAt(actionStart, actionLength);
            state.nextV4SwapLogIndex = _assertUniV4Fills(fills, state.v4SwapLogs, state.nextV4SwapLogIndex, callStart);
        } else if (ZeroExSettlerMainnetSwapIntrospectionCodec.isUniV4VipAction(selector)) {
            ZeroExSettlerV4Fill[] memory fills = callInput.decodeUniV4VipFillsAt(actionStart, actionLength);
            state.nextV4SwapLogIndex = _assertUniV4Fills(fills, state.v4SwapLogs, state.nextV4SwapLogIndex, callStart);
        } else if (!ZeroExSettlerMainnetSwapIntrospectionCodec.isKnownSkippedMainnetAction(selector)) {
            revert("0xSettler: unknown mainnet action");
        }
    }

    function _assertUniV2Action(ZeroExSettlerV2Action memory decoded, uint256 callStart) internal view {
        if (decoded.bps == 0) {
            return;
        }

        ZeroExSettlerV2Snapshot memory snapshot = _readV2Snapshot(decoded.pool, _preCall(callStart));
        PhEvm.Log[] memory logs = _erc20LogsForCall(callStart);

        address outputToken = decoded.zeroForOne ? snapshot.token1 : snapshot.token0;
        uint256 inputAmount = _transferValue(logs, decoded.sellToken, address(0), decoded.pool);
        uint256 outputAmount = _transferValue(logs, outputToken, decoded.pool, address(0));
        require(inputAmount != 0 && outputAmount != 0, "0xSettler: empty UniV2 swap outcome");
        _requireRatioWithinImpact(
            outputAmount,
            inputAmount,
            decoded.zeroForOne ? snapshot.reserve1 : snapshot.reserve0,
            decoded.zeroForOne ? snapshot.reserve0 : snapshot.reserve1
        );
    }

    function _readV2Snapshot(address pool, PhEvm.ForkId memory fork)
        internal
        view
        returns (ZeroExSettlerV2Snapshot memory snapshot)
    {
        (uint112 reserve0, uint112 reserve1,) = abi.decode(
            _viewAt(pool, abi.encodeCall(IZeroExUniV2PoolLike.getReserves, ()), fork), (uint112, uint112, uint32)
        );
        snapshot.token0 = _readAddressAt(pool, abi.encodeCall(IZeroExUniV2PoolLike.token0, ()), fork);
        snapshot.token1 = _readAddressAt(pool, abi.encodeCall(IZeroExUniV2PoolLike.token1, ()), fork);
        snapshot.reserve0 = reserve0;
        snapshot.reserve1 = reserve1;
    }

    function _assertUniV3Action(ZeroExSettlerV3Action memory decoded, uint256 callStart) internal view {
        if (decoded.bps == 0) {
            return;
        }

        PhEvm.Log[] memory logs = _erc20LogsForCall(callStart);
        uint256 offset;
        while (ZeroExSettlerMainnetSwapIntrospectionCodec.hasV3Hop(decoded.path, offset)) {
            _assertUniV3Hop(decoded.path.decodeV3Hop(offset), logs, callStart);
            offset = ZeroExSettlerMainnetSwapIntrospectionCodec.nextV3HopOffset(offset);
        }
    }

    function _assertUniV3Hop(ZeroExSettlerV3Hop memory hop, PhEvm.Log[] memory logs, uint256 callStart) internal view {
        (address token0, address token1, bool zeroForOne) = hop.inputToken < hop.outputToken
            ? (hop.inputToken, hop.outputToken, true)
            : (hop.outputToken, hop.inputToken, false);

        address pool = _deriveV3Pool(hop.forkId, token0, token1, hop.poolId);
        IZeroExUniV3PoolLike poolLike = IZeroExUniV3PoolLike(pool);
        (uint160 sqrtPriceX96,,,,,,) = abi.decode(
            _viewAt(pool, abi.encodeCall(poolLike.slot0, ()), _preCall(callStart)),
            (uint160, int24, uint16, uint16, uint16, uint8, bool)
        );

        _requireV3LikePriceWithinImpact(
            _transferValue(logs, hop.outputToken, pool, address(0)),
            _transferValue(logs, hop.inputToken, address(0), pool),
            sqrtPriceX96,
            zeroForOne
        );
    }

    function _assertUniV4Fills(
        ZeroExSettlerV4Fill[] memory fills,
        PhEvm.Log[] memory swapLogs,
        uint256 nextSwapLogIndex,
        uint256 callStart
    ) internal view returns (uint256) {
        for (uint256 i; i < fills.length; ++i) {
            if (!_isCheckableUniV4Fill(fills[i])) {
                continue;
            }

            nextSwapLogIndex = _assertUniV4Fill(fills[i], swapLogs, nextSwapLogIndex, callStart);
        }
        return nextSwapLogIndex;
    }

    function _assertUniV4Fill(
        ZeroExSettlerV4Fill memory fill,
        PhEvm.Log[] memory swapLogs,
        uint256 nextSwapLogIndex,
        uint256 callStart
    ) internal view returns (uint256) {
        (uint256 logIndex, uint256 inputAmount, uint256 outputAmount) =
            _findUniV4SwapLog(fillsPoolId(fill), fill.zeroForOne, swapLogs, nextSwapLogIndex);
        uint160 sqrtPriceX96 = _readV4SqrtPriceX96(fill.key, _preCall(callStart));
        _requireV3LikePriceWithinImpact(outputAmount, inputAmount, sqrtPriceX96, fill.zeroForOne);
        return logIndex + 1;
    }

    function _requireV3LikePriceWithinImpact(
        uint256 outputAmount,
        uint256 inputAmount,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) internal view {
        require(inputAmount != 0 && outputAmount != 0, "0xSettler: empty swap outcome");

        uint256 priceX96 = ph.mulDivDown(uint256(sqrtPriceX96), uint256(sqrtPriceX96), Q96);
        if (priceX96 == 0) {
            return;
        }

        if (zeroForOne) {
            _requireRatioWithinImpact(outputAmount, inputAmount, priceX96, Q96);
        } else {
            _requireRatioWithinImpact(outputAmount, inputAmount, Q96, priceX96);
        }
    }

    function _requireRatioWithinImpact(uint256 amountOut, uint256 amountIn, uint256 referenceOut, uint256 referenceIn)
        internal
        view
    {
        if (referenceOut == 0 || referenceIn == 0) {
            return;
        }

        require(
            ph.ratioGe(amountOut, amountIn, referenceOut, referenceIn, MAX_PRICE_IMPACT_BPS),
            "0xSettler: intermediate price impact too high"
        );
    }

    function _readV4SqrtPriceX96(IZeroExUniV4PoolManagerLike.PoolKey memory key, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        bytes32 poolId = keccak256(abi.encode(key.token0, key.token1, key.fee, key.tickSpacing, key.hooks));
        bytes32 slot0Slot = keccak256(abi.encode(poolId, UNI_V4_POOLS_SLOT));
        bytes32 raw = abi.decode(
            _viewAt(MAINNET_UNI_V4_POOL_MANAGER, abi.encodeWithSelector(V4_EXTSLOAD_SELECTOR, slot0Slot), fork),
            (bytes32)
        );
        sqrtPriceX96 = uint160(uint256(raw));
    }

    function _deriveV3Pool(uint8 forkId, address token0, address token1, uint24 poolId)
        internal
        pure
        returns (address pool)
    {
        (address factory, bytes32 initHash) = _v3ForkInfo(forkId);
        bytes32 salt =
            poolId == 0 ? keccak256(abi.encode(token0, token1)) : keccak256(abi.encode(token0, token1, poolId));
        pool = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factory, salt, initHash)))));
    }

    function _v3ForkInfo(uint8 forkId) internal pure returns (address factory, bytes32 initHash) {
        if (forkId == UNI_V3_FORK_ID) {
            return (UNI_V3_FACTORY, UNI_V3_INIT_HASH);
        }
        if (forkId == PANCAKE_V3_FORK_ID) {
            return (PANCAKE_V3_FACTORY, PANCAKE_V3_INIT_HASH);
        }
        if (forkId == SUSHI_V3_FORK_ID) {
            return (SUSHI_V3_MAINNET_FACTORY, UNI_V3_INIT_HASH);
        }
        revert("0xSettler: unsupported UniV3 fork");
    }

    function _trackUniV2LegKey(bytes32[] memory seenLegs, uint256 seenCount, ZeroExSettlerV2Action memory decoded)
        internal
        pure
        returns (uint256)
    {
        if (decoded.bps == 0) {
            return seenCount;
        }

        return _trackUniqueLeg(seenLegs, seenCount, _uniV2LegKey(decoded));
    }

    function _trackUniV3LegKeys(bytes32[] memory seenLegs, uint256 seenCount, ZeroExSettlerV3Action memory decoded)
        internal
        pure
        returns (uint256)
    {
        if (decoded.bps == 0) {
            return seenCount;
        }

        uint256 offset;
        while (ZeroExSettlerMainnetSwapIntrospectionCodec.hasV3Hop(decoded.path, offset)) {
            seenCount = _trackUniqueLeg(seenLegs, seenCount, _uniV3LegKey(decoded.path.decodeV3Hop(offset)));
            offset = ZeroExSettlerMainnetSwapIntrospectionCodec.nextV3HopOffset(offset);
        }
        return seenCount;
    }

    function _trackUniqueLeg(bytes32[] memory seenLegs, uint256 seenCount, bytes32 key)
        internal
        pure
        returns (uint256)
    {
        require(seenCount < seenLegs.length, "0xSettler: too many swap legs");
        for (uint256 i; i < seenCount; ++i) {
            require(seenLegs[i] != key, "0xSettler: ambiguous repeated swap leg");
        }

        seenLegs[seenCount] = key;
        return seenCount + 1;
    }

    function _uniV2LegKey(ZeroExSettlerV2Action memory decoded) internal pure returns (bytes32) {
        return keccak256(abi.encode("UNI_V2", decoded.pool, decoded.sellToken, decoded.zeroForOne));
    }

    function _uniV3LegKey(ZeroExSettlerV3Hop memory hop) internal pure returns (bytes32) {
        (address token0, address token1) =
            hop.inputToken < hop.outputToken ? (hop.inputToken, hop.outputToken) : (hop.outputToken, hop.inputToken);
        return keccak256(
            abi.encode("UNI_V3", _deriveV3Pool(hop.forkId, token0, token1, hop.poolId), hop.inputToken, hop.outputToken)
        );
    }

    function _isCheckableUniV4Fill(ZeroExSettlerV4Fill memory fill) internal pure returns (bool) {
        return fill.bps != 0 && fill.sellToken != address(0) && fill.buyToken != address(0);
    }

    function _erc20LogsForCall(uint256 callId) internal view returns (PhEvm.Log[] memory logs) {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: address(0), signature: ERC20_TRANSFER_SIG});
        return ph.getLogsForCall(query, callId);
    }

    function _uniV4SwapLogsForCall(uint256 callId) internal view returns (PhEvm.Log[] memory logs) {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: MAINNET_UNI_V4_POOL_MANAGER, signature: V4_SWAP_SIG});
        return ph.getLogsForCall(query, callId);
    }

    function _transferValue(PhEvm.Log[] memory logs, address token, address from, address to)
        internal
        pure
        returns (uint256 value)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (!_isErc20Transfer(logs[i]) || logs[i].emitter != token) {
                continue;
            }

            if (
                (from == address(0) || _topicAddress(logs[i].topics[1]) == from)
                    && (to == address(0) || _topicAddress(logs[i].topics[2]) == to)
            ) {
                value += abi.decode(logs[i].data, (uint256));
            }
        }
    }

    function _findUniV4SwapLog(bytes32 poolId, bool zeroForOne, PhEvm.Log[] memory swapLogs, uint256 startIndex)
        internal
        pure
        returns (uint256 logIndex, uint256 inputAmount, uint256 outputAmount)
    {
        for (uint256 i = startIndex; i < swapLogs.length; ++i) {
            if (swapLogs[i].topics.length < 2 || swapLogs[i].topics[1] != poolId) {
                continue;
            }

            (int128 amount0, int128 amount1,,,,) =
                abi.decode(swapLogs[i].data, (int128, int128, uint160, uint128, int24, uint24));
            if (zeroForOne) {
                return (i, _negativeMagnitude(amount0), _positiveMagnitude(amount1));
            }
            return (i, _negativeMagnitude(amount1), _positiveMagnitude(amount0));
        }

        revert("0xSettler: missing UniV4 swap log");
    }

    function fillsPoolId(ZeroExSettlerV4Fill memory fill) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(fill.key.token0, fill.key.token1, fill.key.fee, fill.key.tickSpacing, fill.key.hooks));
    }

    function _negativeMagnitude(int128 value) internal pure returns (uint256) {
        require(value < 0, "0xSettler: invalid UniV4 swap delta");
        return uint256(-int256(value));
    }

    function _positiveMagnitude(int128 value) internal pure returns (uint256) {
        require(value > 0, "0xSettler: invalid UniV4 swap delta");
        return uint256(int256(value));
    }
}
