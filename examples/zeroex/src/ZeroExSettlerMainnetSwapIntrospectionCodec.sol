// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IZeroExUniV4PoolManagerLike} from "./ZeroExSettlerInterfaces.sol";

struct ZeroExSettlerV2Action {
    address sellToken;
    address pool;
    uint256 bps;
    bool zeroForOne;
}

struct ZeroExSettlerV2Snapshot {
    address token0;
    address token1;
    uint256 reserve0;
    uint256 reserve1;
}

struct ZeroExSettlerV3Action {
    uint256 bps;
    bytes path;
}

struct ZeroExSettlerV3Hop {
    address inputToken;
    address outputToken;
    uint8 forkId;
    uint24 poolId;
}

struct ZeroExSettlerV4Fill {
    IZeroExUniV4PoolManagerLike.PoolKey key;
    address sellToken;
    address buyToken;
    uint256 bps;
    uint160 sqrtPriceLimitX96;
    bool zeroForOne;
}

/// @notice Pure calldata and packed-path decoding helpers for mainnet 0x Settler swap introspection.
library ZeroExSettlerMainnetSwapIntrospectionCodec {
    address internal constant ETH_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant UNI_V3_SINGLE_HOP_PATH_SIZE = 64;
    uint256 internal constant UNI_V3_PATH_SKIP_HOP_SIZE = 44;
    uint256 internal constant UNI_V4_MIN_FILL_SIZE = 52;

    bytes4 internal constant UNISWAPV2_ACTION =
        bytes4(keccak256("UNISWAPV2(address,address,uint256,address,uint24,uint256)"));
    bytes4 internal constant UNISWAPV3_ACTION = bytes4(keccak256("UNISWAPV3(address,uint256,bytes,uint256)"));
    bytes4 internal constant UNISWAPV4_ACTION =
        bytes4(keccak256("UNISWAPV4(address,address,uint256,bool,uint256,uint256,bytes,uint256)"));

    bytes4 internal constant RFQ_ACTION =
        bytes4(keccak256("RFQ(address,((address,uint256),uint256,uint256),address,bytes,address,uint256)"));
    bytes4 internal constant TRANSFER_FROM_ACTION =
        bytes4(keccak256("TRANSFER_FROM(address,((address,uint256),uint256,uint256),bytes)"));
    bytes4 internal constant METATXN_TRANSFER_FROM_ACTION =
        bytes4(keccak256("METATXN_TRANSFER_FROM(address,((address,uint256),uint256,uint256))"));
    bytes4 internal constant NATIVE_CHECK_ACTION = bytes4(keccak256("NATIVE_CHECK(uint256,uint256)"));
    bytes4 internal constant CHECK_SLIPPAGE_ACTION = bytes4(keccak256("CHECK_SLIPPAGE(bool)"));
    bytes4 internal constant BASIC_ACTION = bytes4(keccak256("BASIC(address,uint256,address,uint256,bytes)"));
    bytes4 internal constant POSITIVE_SLIPPAGE_ACTION =
        bytes4(keccak256("POSITIVE_SLIPPAGE(address,address,uint256,uint256)"));
    bytes4 internal constant BALANCERV3_ACTION =
        bytes4(keccak256("BALANCERV3(address,address,uint256,bool,uint256,uint256,bytes,uint256)"));
    bytes4 internal constant BALANCERV3_VIP_ACTION = bytes4(
        keccak256(
            "BALANCERV3_VIP(address,((address,uint256),uint256,uint256),bool,uint256,uint256,bytes,bytes,uint256)"
        )
    );
    bytes4 internal constant METATXN_BALANCERV3_VIP_ACTION = bytes4(
        keccak256(
            "METATXN_BALANCERV3_VIP(address,((address,uint256),uint256,uint256),bool,uint256,uint256,bytes,uint256)"
        )
    );
    bytes4 internal constant EKUBO_ACTION =
        bytes4(keccak256("EKUBO(address,address,uint256,bool,uint256,uint256,bytes,uint256)"));
    bytes4 internal constant EKUBOV3_ACTION =
        bytes4(keccak256("EKUBOV3(address,address,uint256,bool,uint256,uint256,bytes,uint256)"));
    bytes4 internal constant EKUBOV3_VIP_ACTION = bytes4(
        keccak256("EKUBOV3_VIP(address,((address,uint256),uint256,uint256),bool,uint256,uint256,bytes,bytes,uint256)")
    );
    bytes4 internal constant METATXN_EKUBOV3_VIP_ACTION = bytes4(
        keccak256("METATXN_EKUBOV3_VIP(address,((address,uint256),uint256,uint256),bool,uint256,uint256,bytes,uint256)")
    );
    bytes4 internal constant UNISWAPV3_VIP_ACTION =
        bytes4(keccak256("UNISWAPV3_VIP(address,((address,uint256),uint256,uint256),bytes,bytes,uint256)"));
    bytes4 internal constant METATXN_UNISWAPV3_VIP_ACTION =
        bytes4(keccak256("METATXN_UNISWAPV3_VIP(address,((address,uint256),uint256,uint256),bytes,uint256)"));
    bytes4 internal constant UNISWAPV4_VIP_ACTION = bytes4(
        keccak256("UNISWAPV4_VIP(address,((address,uint256),uint256,uint256),bool,uint256,uint256,bytes,bytes,uint256)")
    );
    bytes4 internal constant METATXN_UNISWAPV4_VIP_ACTION = bytes4(
        keccak256(
            "METATXN_UNISWAPV4_VIP(address,((address,uint256),uint256,uint256),bool,uint256,uint256,bytes,uint256)"
        )
    );
    bytes4 internal constant EULERSWAP_ACTION =
        bytes4(keccak256("EULERSWAP(address,address,uint256,address,bool,uint256)"));
    bytes4 internal constant MAVERICKV2_ACTION =
        bytes4(keccak256("MAVERICKV2(address,address,uint256,address,bool,int32,uint256)"));
    bytes4 internal constant BEBOP_ACTION = bytes4(
        keccak256(
            "BEBOP(address,address,(uint256,address,uint256,address,uint256,uint256,uint256),(bytes,uint256),uint256)"
        )
    );
    bytes4 internal constant DODOV1_ACTION = bytes4(keccak256("DODOV1(address,uint256,address,bool,uint256)"));
    bytes4 internal constant DODOV2_ACTION = bytes4(keccak256("DODOV2(address,address,uint256,address,bool,uint256)"));
    bytes4 internal constant MAKERPSM_ACTION =
        bytes4(keccak256("MAKERPSM(address,uint256,bool,uint256,address,address)"));

    function actionsArrayHead(bytes memory input) internal pure returns (uint256 arrayHead) {
        require(input.length >= 164, "0xSettler: short calldata");

        uint256 actionsOffset = readWord(input, 100);
        arrayHead = 4 + actionsOffset;
        require(arrayHead + 32 <= input.length, "0xSettler: malformed actions");
    }

    function actionsLength(bytes memory input, uint256 arrayHead) internal pure returns (uint256) {
        require(arrayHead + 32 <= input.length, "0xSettler: malformed actions");
        return readWord(input, arrayHead);
    }

    function actionBounds(bytes memory input, uint256 arrayHead, uint256 index)
        internal
        pure
        returns (uint256 dataStart, uint256 dataLength)
    {
        require(arrayHead + 64 + index * 32 <= input.length, "0xSettler: malformed action");

        uint256 elementOffset = readWord(input, arrayHead + 32 + index * 32);
        uint256 elementHead = arrayHead + 32 + elementOffset;
        require(elementHead + 32 <= input.length, "0xSettler: malformed action");

        dataLength = readWord(input, elementHead);
        dataStart = elementHead + 32;
        require(dataStart + dataLength <= input.length, "0xSettler: truncated action");
    }

    function selectorAt(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes4 selector) {
        require(length >= 4 && data.length >= offset + 4, "0xSettler: short action");
        selector = bytes4(
            uint32(uint8(data[offset])) << 24 | uint32(uint8(data[offset + 1])) << 16 | uint32(uint8(data[offset + 2]))
                << 8 | uint32(uint8(data[offset + 3]))
        );
    }

    function copySlice(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes memory result) {
        require(data.length >= offset + length, "0xSettler: truncated bytes");
        result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = data[offset + i];
        }
    }

    function selectorOf(bytes memory data) internal pure returns (bytes4 selector) {
        require(data.length >= 4, "0xSettler: short action");
        selector = bytes4(
            uint32(uint8(data[0])) << 24 | uint32(uint8(data[1])) << 16 | uint32(uint8(data[2])) << 8
                | uint32(uint8(data[3]))
        );
    }

    function isUniV2Action(bytes4 selector) internal pure returns (bool) {
        return selector == UNISWAPV2_ACTION;
    }

    function isUniV3Action(bytes4 selector) internal pure returns (bool) {
        return selector == UNISWAPV3_ACTION;
    }

    function isUniV3VipAction(bytes4 selector) internal pure returns (bool) {
        return selector == UNISWAPV3_VIP_ACTION || selector == METATXN_UNISWAPV3_VIP_ACTION;
    }

    function isUniV4Action(bytes4 selector) internal pure returns (bool) {
        return selector == UNISWAPV4_ACTION;
    }

    function isUniV4VipAction(bytes4 selector) internal pure returns (bool) {
        return selector == UNISWAPV4_VIP_ACTION || selector == METATXN_UNISWAPV4_VIP_ACTION;
    }

    function isKnownSkippedMainnetAction(bytes4 selector) internal pure returns (bool) {
        return selector == RFQ_ACTION || selector == TRANSFER_FROM_ACTION || selector == METATXN_TRANSFER_FROM_ACTION
            || selector == NATIVE_CHECK_ACTION || selector == CHECK_SLIPPAGE_ACTION || selector == BASIC_ACTION
            || selector == POSITIVE_SLIPPAGE_ACTION || selector == BALANCERV3_ACTION
            || selector == BALANCERV3_VIP_ACTION || selector == METATXN_BALANCERV3_VIP_ACTION
            || selector == EKUBO_ACTION || selector == EKUBOV3_ACTION || selector == EKUBOV3_VIP_ACTION
            || selector == METATXN_EKUBOV3_VIP_ACTION || selector == EULERSWAP_ACTION || selector == MAVERICKV2_ACTION
            || selector == BEBOP_ACTION || selector == DODOV1_ACTION || selector == DODOV2_ACTION
            || selector == MAKERPSM_ACTION;
    }

    function decodeUniV2Action(bytes memory action) internal pure returns (ZeroExSettlerV2Action memory decoded) {
        address recipient;
        uint256 amountOutMin;
        uint24 swapInfo;
        (recipient, decoded.sellToken, decoded.bps, decoded.pool, swapInfo, amountOutMin) =
            abi.decode(tail(action), (address, address, uint256, address, uint24, uint256));
        recipient;
        amountOutMin;
        decoded.zeroForOne = (swapInfo & 1) == 1;
    }

    function decodeUniV3Action(bytes memory action) internal pure returns (ZeroExSettlerV3Action memory decoded) {
        address recipient;
        uint256 minAmountOut;
        (recipient, decoded.bps, decoded.path, minAmountOut) =
            abi.decode(tail(action), (address, uint256, bytes, uint256));
        recipient;
        minAmountOut;
    }

    function decodeUniV3VipAction(bytes memory action) internal pure returns (ZeroExSettlerV3Action memory decoded) {
        bytes4 selector = selectorOf(action);
        require(
            selector == UNISWAPV3_VIP_ACTION || selector == METATXN_UNISWAPV3_VIP_ACTION,
            "0xSettler: not UniV3 VIP action"
        );

        decoded.path = readActionBytes(action, 164);
        decoded.bps = 1;
    }

    function decodeV3Hop(bytes memory path, uint256 offset) internal pure returns (ZeroExSettlerV3Hop memory hop) {
        hop.inputToken = readAddress(path, offset);
        hop.forkId = uint8(path[offset + 20]);
        hop.poolId = uint24(uint8(path[offset + 21])) << 16 | uint24(uint8(path[offset + 22])) << 8
            | uint24(uint8(path[offset + 23]));
        hop.outputToken = readAddress(path, offset + 44);
    }

    function hasV3Hop(bytes memory path, uint256 offset) internal pure returns (bool) {
        return path.length >= offset + UNI_V3_SINGLE_HOP_PATH_SIZE;
    }

    function nextV3HopOffset(uint256 offset) internal pure returns (uint256) {
        return offset + UNI_V3_PATH_SKIP_HOP_SIZE;
    }

    function decodeUniV4FillsAt(bytes memory input, uint256 actionStart, uint256 actionLength)
        internal
        pure
        returns (ZeroExSettlerV4Fill[] memory decoded)
    {
        require(actionLength >= 260, "0xSettler: short UniV4 action");

        uint256 argsStart = actionStart + 4;
        address actionSellToken = address(uint160(readWord(input, argsStart + 32)));
        uint256 bps = readWord(input, argsStart + 64);
        if (bps == 0) {
            return decoded;
        }

        (uint256 fillsStart, uint256 fillsLength) = actionBytesBounds(input, actionStart, actionLength, argsStart + 192);
        decoded = decodeUniV4FillsFromSellTokenAt(actionSellToken, input, fillsStart, fillsLength);
    }

    function decodeUniV4VipFillsAt(bytes memory input, uint256 actionStart, uint256 actionLength)
        internal
        pure
        returns (ZeroExSettlerV4Fill[] memory decoded)
    {
        require(actionLength >= 292, "0xSettler: short UniV4 VIP action");

        address sellToken = address(uint160(readWord(input, actionStart + 36)));
        (uint256 fillsStart, uint256 fillsLength) =
            actionBytesBounds(input, actionStart, actionLength, actionStart + 260);
        decoded = decodeUniV4FillsFromSellTokenAt(sellToken, input, fillsStart, fillsLength);
    }

    function decodeUniV4FillsFromSellTokenAt(
        address sellToken,
        bytes memory fills,
        uint256 fillsStart,
        uint256 fillsLength
    ) internal pure returns (ZeroExSettlerV4Fill[] memory decoded) {
        if (fills.length == 0) {
            return decoded;
        }
        require(fills.length >= fillsStart + fillsLength, "0xSettler: truncated UniV4 fills");
        if (fillsLength == 0) {
            return decoded;
        }
        require(fillsLength >= UNI_V4_MIN_FILL_SIZE, "0xSettler: short UniV4 fill");

        ZeroExSettlerV4Fill[] memory scratch = new ZeroExSettlerV4Fill[](fillsLength / UNI_V4_MIN_FILL_SIZE);
        address currentSellToken = sellToken;
        address currentBuyToken;
        uint256 count;
        uint256 cursor = fillsStart;
        uint256 fillsEnd = fillsStart + fillsLength;

        while (cursor < fillsEnd) {
            (scratch[count], cursor) =
                decodeUniV4FillFromTokensAt(currentSellToken, currentBuyToken, fills, cursor, fillsEnd);
            currentSellToken = scratch[count].sellToken;
            currentBuyToken = scratch[count].buyToken;
            ++count;
        }

        decoded = new ZeroExSettlerV4Fill[](count);
        for (uint256 i; i < count; ++i) {
            decoded[i] = scratch[i];
        }
    }

    function decodeUniV4FillFromTokensAt(
        address previousSellToken,
        address previousBuyToken,
        bytes memory fills,
        uint256 fillOffset,
        uint256 fillsEnd
    ) internal pure returns (ZeroExSettlerV4Fill memory decoded, uint256 nextFillOffset) {
        require(fillsEnd >= fillOffset + UNI_V4_MIN_FILL_SIZE, "0xSettler: short UniV4 fill");

        decoded.bps = readUint16(fills, fillOffset);
        decoded.sqrtPriceLimitX96 = uint160(readAddress(fills, fillOffset + 2));
        uint8 packingKey = uint8(fills[fillOffset + 22]);
        uint256 cursor = fillOffset + 23;

        if (packingKey == 0) {
            require(previousBuyToken != address(0), "0xSettler: invalid UniV4 token cache");
            decoded.sellToken = previousSellToken;
            decoded.buyToken = previousBuyToken;
        } else if (packingKey == 1) {
            decoded.sellToken = previousSellToken;
            decoded.buyToken = readAddress(fills, cursor);
            cursor += 20;
        } else if (packingKey == 2) {
            require(previousBuyToken != address(0), "0xSettler: invalid UniV4 token cache");
            decoded.sellToken = previousBuyToken;
            decoded.buyToken = readAddress(fills, cursor);
            cursor += 20;
        } else if (packingKey == 3) {
            decoded.sellToken = readAddress(fills, cursor);
            decoded.buyToken = readAddress(fills, cursor + 20);
            cursor += 40;
        } else {
            revert("0xSettler: unsupported UniV4 fill");
        }

        uint24 fee = readUint24(fills, cursor);
        cursor += 3;
        int24 tickSpacing = int24(readUint24(fills, cursor));
        cursor += 3;
        address hooks = readAddress(fills, cursor);
        cursor += 20;

        uint256 hookDataLength = readUint24(fills, cursor);
        cursor += 3;
        require(cursor + hookDataLength <= fillsEnd, "0xSettler: truncated UniV4 hook data");
        nextFillOffset = cursor + hookDataLength;

        decoded.zeroForOne = decoded.sellToken == ETH_SENTINEL
            || (decoded.buyToken != ETH_SENTINEL && decoded.sellToken < decoded.buyToken);
        decoded.key = IZeroExUniV4PoolManagerLike.PoolKey({
            token0: decoded.zeroForOne ? v4Currency(decoded.sellToken) : v4Currency(decoded.buyToken),
            token1: decoded.zeroForOne ? v4Currency(decoded.buyToken) : v4Currency(decoded.sellToken),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
    }

    function actionBytesBounds(bytes memory input, uint256 actionStart, uint256 actionLength, uint256 offsetWord)
        internal
        pure
        returns (uint256 dataStart, uint256 dataLength)
    {
        require(offsetWord + 32 <= actionStart + actionLength, "0xSettler: malformed bytes");

        uint256 dataHead = actionStart + 4 + readWord(input, offsetWord);
        require(dataHead + 32 <= actionStart + actionLength, "0xSettler: malformed bytes");

        dataLength = readWord(input, dataHead);
        dataStart = dataHead + 32;
        require(dataStart + dataLength <= actionStart + actionLength, "0xSettler: truncated bytes");
    }

    function tail(bytes memory data) internal pure returns (bytes memory result) {
        require(data.length >= 4, "0xSettler: short data");
        result = new bytes(data.length - 4);
        for (uint256 i; i < result.length; ++i) {
            result[i] = data[i + 4];
        }
    }

    function readActionBytes(bytes memory data, uint256 offsetWord) internal pure returns (bytes memory result) {
        require(offsetWord + 32 <= data.length, "0xSettler: malformed bytes");

        uint256 dataHead = 4 + readWord(data, offsetWord);
        require(dataHead + 32 <= data.length, "0xSettler: malformed bytes");

        uint256 length = readWord(data, dataHead);
        uint256 dataStart = dataHead + 32;
        require(dataStart + length <= data.length, "0xSettler: truncated bytes");

        result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = data[dataStart + i];
        }
    }

    function readWord(bytes memory data, uint256 offset) internal pure returns (uint256 word) {
        for (uint256 i; i < 32; ++i) {
            word = (word << 8) | uint8(data[offset + i]);
        }
    }

    function readAddress(bytes memory data, uint256 offset) internal pure returns (address value) {
        require(data.length >= offset + 20, "0xSettler: short packed address");
        uint160 raw;
        for (uint256 i; i < 20; ++i) {
            raw = (raw << 8) | uint160(uint8(data[offset + i]));
        }
        value = address(raw);
    }

    function readUint24(bytes memory data, uint256 offset) internal pure returns (uint24 value) {
        require(data.length >= offset + 3, "0xSettler: short packed uint24");
        value =
            uint24(uint8(data[offset])) << 16 | uint24(uint8(data[offset + 1])) << 8 | uint24(uint8(data[offset + 2]));
    }

    function readUint16(bytes memory data, uint256 offset) internal pure returns (uint16 value) {
        require(data.length >= offset + 2, "0xSettler: short packed uint16");
        value = uint16(uint8(data[offset])) << 8 | uint16(uint8(data[offset + 1]));
    }

    function v4Currency(address token) internal pure returns (address) {
        return token == ETH_SENTINEL ? address(0) : token;
    }
}
