// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../../PhEvm.sol";

import {IEulerEVaultLike} from "./EulerEVaultInterfaces.sol";
import {EulerEVaultSandwichBase, IEulerEVaultSandwichLike} from "./EulerEVaultSandwichHelpers.sol";

/// @title EulerERC4626CallSandwichAssertion
/// @author Phylax Systems
/// @notice "sandwich" pattern for EVK ERC-4626 entry and exit calls.
/// @dev For each successful deposit/mint/withdraw/redeem, the assertion compares:
///      1. calldata decoded from the exact triggered call,
///      2. preview output from immediately before that same call,
///      3. return data and logs emitted after execution of that same call frame.
///      This defends the intra-call expectation that the pre-call preview and post-call result
///      match; it does not claim to prevent unrelated state changes before the transaction lands.
contract EulerERC4626CallSandwichAssertion is EulerEVaultSandwichBase {
    /// @notice Run the same call-sandwich invariant for each ERC-4626 mutator.
    /// @dev `assertErc4626CallWasHonest` once per successful matching EVault call,
    ///      with `ph.context()` pointing at that exact call frame.
    function triggers() external view override {
        registerFnCallTrigger(this.assertErc4626CallWasHonest.selector, IEulerEVaultLike.deposit.selector);
        registerFnCallTrigger(this.assertErc4626CallWasHonest.selector, IEulerEVaultLike.mint.selector);
        registerFnCallTrigger(this.assertErc4626CallWasHonest.selector, IEulerEVaultLike.withdraw.selector);
        registerFnCallTrigger(this.assertErc4626CallWasHonest.selector, IEulerEVaultLike.redeem.selector);
    }

    /// @notice Checks that the triggered ERC-4626 call matches its immediate pre-call preview and same-call event.
    /// @dev A failure means the EVault return value diverged from its pre-call preview, or the event emitted for
    ///      the call frame did not agree with the operation's calldata and post-call return value.
    function assertErc4626CallWasHonest() external view {
        address vault = _vault();
        PhEvm.TriggerContext memory ctx = ph.context();

        // Shared V2 call-frame reads: exact calldata and exact return data for the triggering call.
        bytes memory input = ph.callinputAt(ctx.callStart);
        uint256 actualReturn = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        if (ctx.selector == IEulerEVaultLike.deposit.selector) {
            // deposit(assets, receiver): pre-call previewDeposit must match the post-call shares returned.
            (uint256 assets,) = abi.decode(_stripSelector(input), (uint256, address));
            if (assets != type(uint256).max) {
                uint256 expectedShares = _readUintAt(
                    vault, abi.encodeCall(IEulerEVaultSandwichLike.previewDeposit, (assets)), _preCall(ctx.callStart)
                );
                require(actualReturn == expectedShares, "EulerEVault: deposit return != pre-call preview");
            }

            // Same-call Deposit event must report the requested assets and post-call returned shares.
            _assertDepositLogForCall(vault, ctx.callStart, assets, actualReturn, assets == type(uint256).max);
            return;
        }

        if (ctx.selector == IEulerEVaultLike.mint.selector) {
            // mint(shares, receiver): shares are the input, returned assets must match pre-call previewMint.
            (uint256 shares,) = abi.decode(_stripSelector(input), (uint256, address));
            uint256 expectedAssets = _readUintAt(
                vault, abi.encodeCall(IEulerEVaultSandwichLike.previewMint, (shares)), _preCall(ctx.callStart)
            );
            require(actualReturn == expectedAssets, "EulerEVault: mint return != pre-call preview");

            // mint must report returned assets and requested shares.
            _assertDepositLogForCall(vault, ctx.callStart, actualReturn, shares, false);
            return;
        }

        if (ctx.selector == IEulerEVaultLike.withdraw.selector) {
            // withdraw(assets, receiver, owner): assets are the input, returned shares match pre-call previewWithdraw.
            (uint256 assets,,) = abi.decode(_stripSelector(input), (uint256, address, address));
            uint256 expectedShares = _readUintAt(
                vault, abi.encodeCall(IEulerEVaultSandwichLike.previewWithdraw, (assets)), _preCall(ctx.callStart)
            );
            require(actualReturn == expectedShares, "EulerEVault: withdraw return != pre-call preview");

            // Same-call Withdraw event must report requested assets and returned burned shares.
            _assertWithdrawLogForCall(vault, ctx.callStart, assets, actualReturn, false);
            return;
        }

        if (ctx.selector == IEulerEVaultLike.redeem.selector) {
            // redeem(shares, receiver, owner): shares are the input, returned assets match pre-call previewRedeem.
            (uint256 shares,,) = abi.decode(_stripSelector(input), (uint256, address, address));
            if (shares != type(uint256).max) {
                uint256 expectedAssets = _readUintAt(
                    vault, abi.encodeCall(IEulerEVaultSandwichLike.previewRedeem, (shares)), _preCall(ctx.callStart)
                );
                require(actualReturn == expectedAssets, "EulerEVault: redeem return != pre-call preview");
            }

            // Same-call Withdraw event must report returned assets and requested redeemed shares.
            _assertWithdrawLogForCall(vault, ctx.callStart, actualReturn, shares, shares == type(uint256).max);
            return;
        }

        revert("EulerEVault: unsupported selector");
    }
}
