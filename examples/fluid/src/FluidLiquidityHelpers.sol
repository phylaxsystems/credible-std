// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IZircuitPoolLike {
    function balance(address token_, address staker_) external view returns (uint256);
}

/// @title FluidLiquidityBase
/// @author Phylax Systems
/// @notice Shared reads for assertions installed on the Fluid Liquidity Layer singleton.
/// @dev The Liquidity Layer is one upgradeable proxy that custodies every token for every Fluid
///      protocol. These helpers decode its packed per-token accounting directly from storage so an
///      assertion never has to trust a resolver or re-implement interest accrual:
///      - `_exchangePricesAndConfig[token]` lives at mapping base slot 5 and packs the supply/borrow
///        exchange prices (plain 64-bit values scaled by 1e12).
///      - `_totalAmounts[token]` lives at mapping base slot 7 and packs four BigMath (56|8) fields:
///        supply-with-interest (raw), supply-interest-free, borrow-with-interest (raw),
///        borrow-interest-free.
///      Token amounts with interest are `raw * exchangePrice / 1e12 + interestFree`.
///      Slot numbers and bit offsets are from Fluid's `liquiditySlotsLink.sol`; BigMath decode is
///      from `bigMathMinified.sol` (coefficient = field >> 8, exponent = field & 0xFF).
abstract contract FluidLiquidityBase is Assertion {
    /// @notice Native token sentinel; balances of this "token" cannot be read via ERC20 balanceOf.
    address internal constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Mainnet Liquid staking tokens Fluid explicitly counts as external Liquidity custody.
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant WEETHS = 0x917ceE801a67f933F2e6b33fC0cD1ED2d5909D88;
    address internal constant ZIRCUIT = 0xF047ab4c75cebf0eB9ed34Ae2c186f3611aEAfa6;

    /// @notice Fluid stores supply/borrow exchange prices scaled by 1e12.
    uint256 internal constant EXCHANGE_PRICES_PRECISION = 1e12;

    /// @notice Mapping base slots in the Liquidity Layer storage layout.
    uint256 internal constant SLOT_EXCHANGE_PRICES_AND_CONFIG = 5;
    uint256 internal constant SLOT_TOTAL_AMOUNTS = 7;

    /// @notice Bit offsets inside the `_exchangePricesAndConfig[token]` word.
    uint256 internal constant BITS_SUPPLY_EXCHANGE_PRICE = 91;
    uint256 internal constant BITS_BORROW_EXCHANGE_PRICE = 155;

    /// @notice Bit offsets inside the `_totalAmounts[token]` word.
    uint256 internal constant BITS_SUPPLY_WITH_INTEREST = 0;
    uint256 internal constant BITS_SUPPLY_INTEREST_FREE = 64;
    uint256 internal constant BITS_BORROW_WITH_INTEREST = 128;
    uint256 internal constant BITS_BORROW_INTEREST_FREE = 192;

    uint256 internal constant MASK_64 = 0xFFFFFFFFFFFFFFFF;
    uint256 internal constant BIGMATH_EXPONENT_MASK = 0xFF;

    /// @notice The monitored Liquidity Layer is always the assertion adopter.
    function _liquidity() internal view returns (address) {
        return ph.getAssertionAdopter();
    }

    /// @notice Token-with-interest totals for `token` at a snapshot, using the Liquidity Layer's
    ///         stored exchange prices (a self-consistent snapshot against the held balance).
    /// @return totalSupply Total amount owed to suppliers (token units).
    /// @return totalBorrow Total amount owed by borrowers (token units).
    function _liquidityTotals(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 totalSupply, uint256 totalBorrow)
    {
        uint256 epac = _readSlot(_exchangePricesSlot(token), fork);
        uint256 supplyExchangePrice = (epac >> BITS_SUPPLY_EXCHANGE_PRICE) & MASK_64;
        uint256 borrowExchangePrice = (epac >> BITS_BORROW_EXCHANGE_PRICE) & MASK_64;

        uint256 amounts = _readSlot(_totalAmountsSlot(token), fork);
        uint256 supplyRaw = _decodeBigMath((amounts >> BITS_SUPPLY_WITH_INTEREST) & MASK_64);
        uint256 supplyInterestFree = _decodeBigMath((amounts >> BITS_SUPPLY_INTEREST_FREE) & MASK_64);
        uint256 borrowRaw = _decodeBigMath((amounts >> BITS_BORROW_WITH_INTEREST) & MASK_64);
        uint256 borrowInterestFree = _decodeBigMath((amounts >> BITS_BORROW_INTEREST_FREE) & MASK_64);

        totalSupply = supplyInterestFree + (supplyRaw * supplyExchangePrice) / EXCHANGE_PRICES_PRECISION;
        totalBorrow = borrowInterestFree + (borrowRaw * borrowExchangePrice) / EXCHANGE_PRICES_PRECISION;
    }

    /// @notice Stored supply and borrow exchange prices for `token` at a snapshot.
    function _liquidityExchangePrices(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 supplyExchangePrice, uint256 borrowExchangePrice)
    {
        uint256 epac = _readSlot(_exchangePricesSlot(token), fork);
        supplyExchangePrice = (epac >> BITS_SUPPLY_EXCHANGE_PRICE) & MASK_64;
        borrowExchangePrice = (epac >> BITS_BORROW_EXCHANGE_PRICE) & MASK_64;
    }

    /// @dev `mapping(address => ...)` slot is `keccak256(abi.encode(key, baseSlot))`. Both operands
    ///      are fixed 32-byte words, so we hash them straight from the EVM scratch space (0x00-0x40)
    ///      instead of allocating an `abi.encode` buffer — identical result, no memory growth, and it
    ///      clears the `asm-keccak256` lint. `mstore(0x00, token)` left-pads the address exactly as
    ///      `abi.encode` would.
    function _exchangePricesSlot(address token) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, token)
            mstore(0x20, SLOT_EXCHANGE_PRICES_AND_CONFIG)
            slot := keccak256(0x00, 0x40)
        }
    }

    function _totalAmountsSlot(address token) internal pure returns (bytes32 slot) {
        assembly {
            mstore(0x00, token)
            mstore(0x20, SLOT_TOTAL_AMOUNTS)
            slot := keccak256(0x00, 0x40)
        }
    }

    function _readSlot(bytes32 slot, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return uint256(ph.loadStateAt(_liquidity(), slot, fork));
    }

    /// @notice Reads Fluid-recognized custody for `token`, including mainnet external balances.
    function _liquidityCustodyBalance(address token, address liquidity, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        balance = _readBalanceAt(token, liquidity, fork);
        balance += _liquidityExternalBalance(token, liquidity, fork);
    }

    /// @notice Mainnet weETH/weETHs can sit in Zircuit while still backing Liquidity accounting.
    function _liquidityExternalBalance(address token, address liquidity, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        if (block.chainid != 1 || !_hasFluidExternalCustody(token)) return 0;
        return _readUintAt(ZIRCUIT, abi.encodeCall(IZircuitPoolLike.balance, (token, liquidity)), fork);
    }

    function _hasFluidExternalCustody(address token) internal pure returns (bool) {
        return token == WEETH || token == WEETHS;
    }

    /// @notice Decodes a 64-bit Fluid BigMath field: value = coefficient << exponent.
    function _decodeBigMath(uint256 field) internal pure returns (uint256) {
        uint256 coefficient = field >> 8;
        uint256 exponent = field & BIGMATH_EXPONENT_MASK;
        return coefficient << exponent;
    }

    /// @notice Reads the ABI word for `argIndex` of a call's arguments as an `int256`.
    /// @dev `input` is the selector-stripped argument tail as returned by `ph.matchingCalls(...).input`
    ///      (and the `ph.get*CallInputs` family): the 4-byte selector is the query key and is NOT
    ///      present, so arg `argIndex` sits at byte offset `argIndex * 32`. Do not add a 4-byte
    ///      selector offset here. If a caller ever sources selector-prefixed calldata (e.g.
    ///      `ph.callinputAt`), it must strip the leading selector before calling this.
    function _int256Arg(bytes memory input, uint256 argIndex) internal pure returns (int256 value) {
        uint256 offset = argIndex * 32;
        require(input.length >= offset + 32, "Fluid: malformed calldata");
        assembly {
            value := mload(add(add(input, 0x20), offset))
        }
    }

    /// @notice Reads the ABI word for `argIndex` of a call's arguments as an `address`.
    /// @dev Same selector-stripped `input` contract as `_int256Arg`.
    function _addressArg(bytes memory input, uint256 argIndex) internal pure returns (address account) {
        uint256 offset = argIndex * 32;
        require(input.length >= offset + 32, "Fluid: malformed calldata");
        assembly {
            account := and(mload(add(add(input, 0x20), offset)), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}
