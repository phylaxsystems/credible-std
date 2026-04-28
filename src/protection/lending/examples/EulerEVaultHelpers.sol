// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";

import {IEulerEVaultLike} from "./EulerEVaultInterfaces.sol";

/// @title EulerEVaultBase
/// @author Phylax Systems
/// @notice Shared helpers for factory-scoped Euler Vault Kit EVault assertions.
/// @dev These examples are intended to be installed on each concrete EVault adopter. The
///      monitored vault is therefore read from `ph.getAssertionAdopter()` at assertion time.
abstract contract EulerEVaultBase is Assertion {
    /// @notice EVK virtual deposit used by `ConversionHelpers.conversionTotals()`.
    uint256 internal constant VIRTUAL_DEPOSIT_AMOUNT = 1e6;

    /// @notice Base slot for `vaultStorage.users` in the checked EVK layout.
    /// @dev EVK storage is `initialized` at slot 0, `snapshot` at slot 1, and
    ///      `vaultStorage` at slot 2. `VaultStorage.users` is field 11, so the
    ///      mapping base slot is `2 + 11 = 13`.
    bytes32 internal constant USERS_MAPPING_SLOT = bytes32(uint256(13));

    bytes32 internal constant DEBT_SOCIALIZED_SIG = keccak256("DebtSocialized(address,uint256)");
    bytes32 internal constant LIQUIDATE_SIG = keccak256("Liquidate(address,address,address,uint256,uint256)");

    uint256 internal constant SHARES_MASK = 0x000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant OWED_MASK = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000;
    uint256 internal constant OWED_OFFSET = 112;

    function _vault() internal view returns (address) {
        return ph.getAssertionAdopter();
    }

    function _totalAssetsAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IEulerEVaultLike.totalAssets, ()), fork);
    }

    function _totalSupplyAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IEulerEVaultLike.totalSupply, ()), fork);
    }

    function _debtOfExactAt(address vault, address account, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(IEulerEVaultLike.debtOfExact, (account)), fork);
    }

    function _topicAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }

    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "EulerEVault: short calldata");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }

    function _eventAmount(bytes memory data) internal pure returns (uint256 amount) {
        require(data.length >= 32, "EulerEVault: malformed event data");
        amount = abi.decode(data, (uint256));
    }

    function _rawShares(bytes32 packedUserData) internal pure returns (uint256) {
        return uint256(packedUserData) & SHARES_MASK;
    }

    function _rawOwed(bytes32 packedUserData) internal pure returns (uint256) {
        return (uint256(packedUserData) & OWED_MASK) >> OWED_OFFSET;
    }

    function _keyToAddress(bytes memory key) internal pure returns (address account) {
        require(key.length == 32, "EulerEVault: non-address mapping key");
        account = abi.decode(key, (address));
    }
}
