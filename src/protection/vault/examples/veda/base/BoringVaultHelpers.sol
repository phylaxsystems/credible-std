// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../../../Assertion.sol";
import {PhEvm} from "../../../../../PhEvm.sol";

import {IBoringAccountantLike, IBoringVaultLike} from "./BoringVaultInterfaces.sol";

/// @title BoringVaultHelpers
/// @author Phylax Systems
/// @notice Shared fork-aware state accessors for Boring Vault example assertions.
abstract contract BoringVaultHelpers is Assertion {
    /// @notice BoringVault share token and custody contract being monitored.
    address internal immutable vault;

    /// @notice Accountant used by the teller to price deposits and withdrawals.
    address internal immutable accountant;

    /// @notice One full vault share, scaled to the vault share-token decimals.
    uint256 internal immutable ONE_SHARE;

    constructor(address vault_, address accountant_, uint8 vaultDecimals_) {
        vault = vault_;
        accountant = accountant_;
        ONE_SHARE = 10 ** uint256(vaultDecimals_);
    }

    function _totalSupplyAt(PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IBoringVaultLike.totalSupply, ()), fork);
    }

    function _shareBalanceAt(address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(vault, account, fork);
    }

    function _assetBalanceAt(address asset, address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readBalanceAt(asset, account, fork);
    }

    function _rateInQuoteAt(address quote, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(accountant, abi.encodeCall(IBoringAccountantLike.getRateInQuote, (quote)), fork);
    }

    function _maxSharesForDepositAt(address asset, uint256 assetAmount, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        uint256 rate = _rateInQuoteAt(asset, fork);
        require(rate > 0, "BoringVault: zero quote rate");
        return ph.mulDivDown(assetAmount, ONE_SHARE, rate);
    }

    function _maxAssetsForExitAt(address asset, uint256 shareAmount, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        uint256 rate = _rateInQuoteAt(asset, fork);
        require(rate > 0, "BoringVault: zero quote rate");
        return ph.mulDivDown(shareAmount, rate, ONE_SHARE);
    }

    /// @notice Strip the 4-byte selector from raw call input bytes.
    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "BoringVault: input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }
}
