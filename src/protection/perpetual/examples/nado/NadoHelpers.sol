// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";

import {INadoErc20MetadataLike, INadoSpotEngineLike} from "./NadoInterfaces.sol";

/// @title NadoHelpers
/// @author Phylax Systems
/// @notice Shared fork-aware reads and calldata decoding helpers for Nado assertions.
abstract contract NadoHelpers is Assertion {
    bytes32 internal constant X_ACCOUNT = bytes32(uint256(1));
    uint256 internal constant MAX_DECIMALS = 18;
    uint256 internal constant INT128_MAX = uint256(uint128(type(int128).max));

    address public immutable endpoint;
    address public immutable clearinghouse;
    address public immutable spotEngine;
    address public immutable quoteAsset;
    address public immutable withdrawPool;
    uint256 public immutable collateralDeltaToleranceX18;

    constructor(
        address endpoint_,
        address clearinghouse_,
        address spotEngine_,
        address quoteAsset_,
        address withdrawPool_,
        uint256 collateralDeltaToleranceX18_
    ) {
        endpoint = endpoint_;
        clearinghouse = clearinghouse_;
        spotEngine = spotEngine_;
        quoteAsset = quoteAsset_;
        withdrawPool = withdrawPool_;
        collateralDeltaToleranceX18 = collateralDeltaToleranceX18_;
    }

    function _spotBalanceAt(uint32 productId, bytes32 subaccount, PhEvm.ForkId memory fork)
        internal
        view
        returns (int128 amount)
    {
        INadoSpotEngineLike.Balance memory balance = abi.decode(
            _viewAt(spotEngine, abi.encodeCall(INadoSpotEngineLike.getBalance, (productId, subaccount)), fork),
            (INadoSpotEngineLike.Balance)
        );
        return balance.amount;
    }

    function _productTokenAt(uint32 productId, PhEvm.ForkId memory fork) internal view returns (address token) {
        INadoSpotEngineLike.Config memory config = abi.decode(
            _viewAt(spotEngine, abi.encodeCall(INadoSpotEngineLike.getConfig, (productId)), fork),
            (INadoSpotEngineLike.Config)
        );
        return config.token;
    }

    function _tokenDecimalsAt(address token, PhEvm.ForkId memory fork) internal view returns (uint8 decimals) {
        return _readUint8At(token, abi.encodeCall(INadoErc20MetadataLike.decimals, ()), fork);
    }

    function _clearinghouseTokenBalanceAt(address token, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 balance)
    {
        return _readBalanceAt(token, clearinghouse, fork);
    }

    function _realizedAmountX18(uint128 amount, uint8 decimals) internal pure returns (int256 realizedAmount) {
        require(decimals <= MAX_DECIMALS, "Nado: unsupported token decimals");

        uint256 scale = 10 ** (MAX_DECIMALS - decimals);
        uint256 scaledAmount = uint256(amount) * scale;
        require(scaledAmount <= INT128_MAX, "Nado: realized amount overflow");

        // casting to int256 is safe because scaledAmount is bounded by INT128_MAX above.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(scaledAmount);
    }

    function _assertApproxEq(int256 actual, int256 expected, uint256 tolerance, string memory reason) internal pure {
        require(tolerance <= INT128_MAX, "Nado: tolerance too large");

        // casting to int256 is safe because tolerance is bounded by INT128_MAX above.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedTolerance = int256(tolerance);
        int256 lower = expected - signedTolerance;
        int256 upper = expected + signedTolerance;
        require(actual >= lower && actual <= upper, reason);
    }

    function _assertTokenDelta(uint256 preBalance, uint256 postBalance, uint128 amount, string memory reason)
        internal
        pure
    {
        require(preBalance >= postBalance, reason);
        require(preBalance - postBalance == uint256(amount), reason);
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "Nado: short calldata");

        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }

    function _stripTransactionType(bytes memory transaction) internal pure returns (bytes memory args) {
        require(transaction.length >= 1, "Nado: short transaction");

        args = new bytes(transaction.length - 1);
        for (uint256 i; i < args.length; ++i) {
            args[i] = transaction[i + 1];
        }
    }

    function _viewFailureMessage() internal pure override returns (string memory) {
        return "Nado: staticcallAt failed";
    }
}
