// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {ICapLenderLike, ICapVaultBalanceLike} from "./CapLiquidationInterfaces.sol";

/// @title CapLiquidationHelpers
/// @author Phylax Systems
/// @notice Triggered-call resolution and fork-aware reads for the Cap liquidation assertion.
/// @dev All protocol values are read in asset units (no oracle/decimal scaling needed): the
///      checks compare an agent's debt and the vault's claimable backing across the snapshots
///      bracketing a single `liquidate` call.
abstract contract CapLiquidationHelpers is Assertion {
    /// @dev Gas budget for nested static reads against a fork snapshot.
    uint64 internal constant READ_GAS = 3_000_000;

    /// @dev Decoded view of the `liquidate` call this assertion invocation is checking.
    struct LiquidationCall {
        address agent;
        address asset;
        uint256 amount;
        uint256 callStart;
        uint256 callEnd;
    }

    /// @notice Resolves the specific `liquidate` call that fired this assertion.
    /// @dev Matches the triggering call by id and decodes `(agent, asset, amount)` from its args.
    ///      `getAllCallInputs(...).input` is the calldata args WITHOUT the 4-byte selector, so it
    ///      decodes directly as the argument tuple.
    function _resolveLiquidation() internal view returns (LiquidationCall memory liq) {
        PhEvm.TriggerContext memory ctx = ph.context();
        PhEvm.CallInputs[] memory calls = ph.getAllCallInputs(ph.getAssertionAdopter(), ctx.selector);

        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].id == ctx.callStart) {
                (address agent, address asset, uint256 amount,) =
                    abi.decode(calls[i].input, (address, address, uint256, uint256));
                return LiquidationCall({
                    agent: agent, asset: asset, amount: amount, callStart: ctx.callStart, callEnd: ctx.callEnd
                });
            }
        }

        revert("CapLiquidation: triggered call not found");
    }

    /// @notice Agent's total debt for an asset at a snapshot.
    function _debtAt(address agent, address asset, PhEvm.ForkId memory fork) internal view returns (uint256) {
        return _readUint(ph.getAssertionAdopter(), abi.encodeCall(ICapLenderLike.debt, (agent, asset)), fork);
    }

    /// @notice Vault custodying the backing for an asset at a snapshot.
    function _vaultFor(address asset, PhEvm.ForkId memory fork) internal view returns (address vault) {
        PhEvm.StaticCallResult memory res = ph.staticcallAt(
            ph.getAssertionAdopter(), abi.encodeCall(ICapLenderLike.reservesData, (asset)), READ_GAS, fork
        );
        require(res.ok && res.data.length >= 224, "CapLiquidation: reserves read failed");
        (, vault,,,,,) = abi.decode(res.data, (uint256, address, address, address, uint8, bool, uint256));
        require(vault != address(0), "CapLiquidation: unknown reserve");
    }

    /// @notice Vault's claimable backing for an asset at a snapshot.
    function _availableBalanceAt(address vault, address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256)
    {
        return _readUint(vault, abi.encodeCall(ICapVaultBalanceLike.availableBalance, (asset)), fork);
    }

    /// @notice Restaker interest the liquidation will fund from the vault at a snapshot.
    function _realizedRestakerInterestAt(address agent, address asset, PhEvm.ForkId memory fork)
        internal
        view
        returns (uint256 realized)
    {
        PhEvm.StaticCallResult memory res = ph.staticcallAt(
            ph.getAssertionAdopter(),
            abi.encodeCall(ICapLenderLike.maxRestakerRealization, (agent, asset)),
            READ_GAS,
            fork
        );
        require(res.ok && res.data.length >= 64, "CapLiquidation: realization read failed");
        (realized,) = abi.decode(res.data, (uint256, uint256));
    }

    function _readUint(address target, bytes memory data, PhEvm.ForkId memory fork)
        private
        view
        returns (uint256 result)
    {
        PhEvm.StaticCallResult memory res = ph.staticcallAt(target, data, READ_GAS, fork);
        require(res.ok && res.data.length >= 32, "CapLiquidation: read failed");
        result = abi.decode(res.data, (uint256));
    }
}
