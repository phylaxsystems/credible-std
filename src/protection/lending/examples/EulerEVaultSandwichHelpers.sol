// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../../PhEvm.sol";

import {EulerEVaultBase} from "./EulerEVaultHelpers.sol";
import {IEulerEVaultLike} from "./EulerEVaultInterfaces.sol";

/// @notice Minimal ERC-4626 preview surface used by the Euler sandwich assertion.
interface IEulerEVaultSandwichLike is IEulerEVaultLike {
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
}

/// @title EulerEVaultSandwichBase
/// @author Phylax Systems
/// @notice Shared event-log helpers for EVK ERC-4626 call sandwich assertions.
abstract contract EulerEVaultSandwichBase is EulerEVaultBase {
    bytes32 internal constant DEPOSIT_SIG = keccak256("Deposit(address,address,uint256,uint256)");
    bytes32 internal constant WITHDRAW_SIG = keccak256("Withdraw(address,address,address,uint256,uint256)");

    function _assertDepositLogForCall(
        address vault,
        uint256 callId,
        uint256 expectedAssets,
        uint256 expectedShares,
        bool assetAmountWasDynamic
    ) internal view {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: DEPOSIT_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);

        if (expectedShares == 0) {
            require(logs.length == 0, "EulerEVault: zero deposit emitted event");
            return;
        }

        require(logs.length == 1, "EulerEVault: expected one Deposit event");
        (uint256 assets, uint256 shares) = abi.decode(logs[0].data, (uint256, uint256));
        if (!assetAmountWasDynamic) {
            require(assets == expectedAssets, "EulerEVault: Deposit assets mismatch");
        }
        require(shares == expectedShares, "EulerEVault: Deposit shares mismatch");
    }

    function _assertWithdrawLogForCall(
        address vault,
        uint256 callId,
        uint256 expectedAssets,
        uint256 expectedShares,
        bool shareAmountWasDynamic
    ) internal view {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: WITHDRAW_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);

        if (expectedAssets == 0 || expectedShares == 0) {
            require(logs.length == 0, "EulerEVault: zero withdraw emitted event");
            return;
        }

        require(logs.length == 1, "EulerEVault: expected one Withdraw event");
        (uint256 assets, uint256 shares) = abi.decode(logs[0].data, (uint256, uint256));
        require(assets == expectedAssets, "EulerEVault: Withdraw assets mismatch");
        if (!shareAmountWasDynamic) {
            require(shares == expectedShares, "EulerEVault: Withdraw shares mismatch");
        }
    }
}
