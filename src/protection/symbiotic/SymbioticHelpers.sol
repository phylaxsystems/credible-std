// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {
    ISymbioticOpNetVaultAutoDeployLike,
    ISymbioticVaultLike,
    ISymbioticVotingPowerProviderLike
} from "./SymbioticInterfaces.sol";

/// @title SymbioticHelpers
/// @author Phylax Systems
/// @notice Shared reads and small utilities used by Symbiotic relay- and vault-side assertions.
abstract contract SymbioticHelpers is Assertion {
    function _currentEpochAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.currentEpoch, ()), fork);
    }

    function _depositWhitelistAt(address vault, PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(vault, abi.encodeCall(ISymbioticVaultLike.depositWhitelist, ()), fork);
    }

    function _isDepositorWhitelistedAt(address vault, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool)
    {
        return _readBoolAt(vault, abi.encodeCall(ISymbioticVaultLike.isDepositorWhitelisted, (account)), fork);
    }

    function _isDepositLimitAt(address vault, PhEvm.ForkId memory fork) internal view returns (bool) {
        return _readBoolAt(vault, abi.encodeCall(ISymbioticVaultLike.isDepositLimit, ()), fork);
    }

    function _depositLimitAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.depositLimit, ()), fork);
    }

    function _activeStakeAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.activeStake, ()), fork);
    }

    function _activeSharesAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.activeShares, ()), fork);
    }

    function _activeSharesOfAt(address vault, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.activeSharesOf, (account)), fork);
    }

    function _withdrawalsAt(address vault, uint256 epoch, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.withdrawals, (epoch)), fork);
    }

    function _withdrawalSharesAt(address vault, uint256 epoch, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.withdrawalShares, (epoch)), fork);
    }

    function _withdrawalSharesOfAt(address vault, uint256 epoch, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.withdrawalSharesOf, (epoch, account)), fork);
    }

    function _isWithdrawalsClaimedAt(address vault, uint256 epoch, address account, PhEvm.ForkId memory fork)
        internal
        view
        returns (bool)
    {
        return _readBoolAt(vault, abi.encodeCall(ISymbioticVaultLike.isWithdrawalsClaimed, (epoch, account)), fork);
    }

    function _totalStakeAt(address vault, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUintAt(vault, abi.encodeCall(ISymbioticVaultLike.totalStake, ()), fork);
    }

    function _asProvider(address provider) internal pure returns (ISymbioticVotingPowerProviderLike) {
        return ISymbioticVotingPowerProviderLike(provider);
    }

    function _asAutoDeploy(address provider) internal pure returns (ISymbioticOpNetVaultAutoDeployLike) {
        return ISymbioticOpNetVaultAutoDeployLike(provider);
    }

    /// @notice Returns the trigger call matching the current `TriggerContext` for `target`.
    function _currentTriggerCall(address target, PhEvm.TriggerContext memory ctx)
        internal
        view
        returns (PhEvm.TriggerCall memory)
    {
        PhEvm.TriggerCall[] memory calls = _matchingCalls(target, ctx.selector, 256);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].callId == ctx.callStart) {
                return calls[i];
            }
        }
        revert("SymbioticHelpers: missing trigger call");
    }

    /// @notice Drops the 4-byte selector prefix from ABI-encoded calldata.
    function _stripSelector(bytes memory input) internal pure returns (bytes memory args) {
        require(input.length >= 4, "SymbioticHelpers: input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = input[i + 4];
        }
    }

    function _containsAddress(address[] memory values, address needle) internal pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == needle) {
                return true;
            }
        }
        return false;
    }

    function _findVaultValue(ISymbioticVotingPowerProviderLike.VaultValue[] memory values, address vault_)
        internal
        pure
        returns (bool found, uint256 value)
    {
        for (uint256 i; i < values.length; ++i) {
            if (values[i].vault == vault_) {
                return (true, values[i].value);
            }
        }
        return (false, 0);
    }
}
