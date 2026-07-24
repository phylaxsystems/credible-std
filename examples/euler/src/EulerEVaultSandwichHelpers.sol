// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";

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
        address expectedOwner,
        uint256 expectedAssets,
        uint256 expectedShares
    ) internal view {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: DEPOSIT_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);

        if (expectedShares == 0) {
            require(logs.length == 0, "EulerEVault: zero deposit emitted event");
            return;
        }

        require(logs.length == 1, "EulerEVault: expected one Deposit event");
        require(logs[0].topics.length >= 3, "EulerEVault: malformed Deposit topics");
        require(address(uint160(uint256(logs[0].topics[2]))) == expectedOwner, "EulerEVault: Deposit owner mismatch");
        (uint256 assets, uint256 shares) = abi.decode(logs[0].data, (uint256, uint256));
        require(assets == expectedAssets, "EulerEVault: Deposit assets mismatch");
        require(shares == expectedShares, "EulerEVault: Deposit shares mismatch");
    }

    function _assertWithdrawLogForCall(
        address vault,
        uint256 callId,
        address expectedReceiver,
        address expectedOwner,
        uint256 expectedAssets,
        uint256 expectedShares
    ) internal view {
        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: WITHDRAW_SIG});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, callId);

        if (expectedAssets == 0 || expectedShares == 0) {
            require(logs.length == 0, "EulerEVault: zero withdraw emitted event");
            return;
        }

        require(logs.length == 1, "EulerEVault: expected one Withdraw event");
        require(logs[0].topics.length >= 4, "EulerEVault: malformed Withdraw topics");
        require(
            address(uint160(uint256(logs[0].topics[2]))) == expectedReceiver,
            "EulerEVault: Withdraw receiver mismatch"
        );
        require(address(uint160(uint256(logs[0].topics[3]))) == expectedOwner, "EulerEVault: Withdraw owner mismatch");
        (uint256 assets, uint256 shares) = abi.decode(logs[0].data, (uint256, uint256));
        require(assets == expectedAssets, "EulerEVault: Withdraw assets mismatch");
        require(shares == expectedShares, "EulerEVault: Withdraw shares mismatch");
    }

    function _assertSharesIncreasedBy(
        address vault,
        address receiver,
        uint256 shares,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        uint256 beforeBalance = _readBalanceAt(vault, receiver, pre);
        uint256 afterBalance = _readBalanceAt(vault, receiver, post);
        require(afterBalance >= beforeBalance, "EulerEVault: receiver share balance decreased");
        require(afterBalance - beforeBalance == shares, "EulerEVault: wrong receiver share mint");
    }

    function _assertSharesDecreasedBy(
        address vault,
        address owner,
        uint256 shares,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        uint256 beforeBalance = _readBalanceAt(vault, owner, pre);
        uint256 afterBalance = _readBalanceAt(vault, owner, post);
        require(beforeBalance >= afterBalance, "EulerEVault: owner share balance increased");
        require(beforeBalance - afterBalance == shares, "EulerEVault: wrong owner share burn");
    }

    function _assertReceiverAssetsIncreasedBy(
        address vault,
        address receiver,
        uint256 assets,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        address underlying = _readAddressAt(vault, abi.encodeCall(IEulerEVaultLike.asset, ()), pre);
        uint256 beforeBalance = _readBalanceAt(underlying, receiver, pre);
        uint256 afterBalance = _readBalanceAt(underlying, receiver, post);
        require(afterBalance >= beforeBalance, "EulerEVault: receiver asset balance decreased");
        require(afterBalance - beforeBalance == assets, "EulerEVault: wrong receiver asset payment");
    }

    function _assertVaultAssetsIncreasedBy(
        address vault,
        uint256 assets,
        PhEvm.ForkId memory pre,
        PhEvm.ForkId memory post
    ) internal view {
        address underlying = _readAddressAt(vault, abi.encodeCall(IEulerEVaultLike.asset, ()), pre);
        uint256 beforeBalance = _readBalanceAt(underlying, vault, pre);
        uint256 afterBalance = _readBalanceAt(underlying, vault, post);
        require(afterBalance >= beforeBalance, "EulerEVault: vault asset balance decreased");
        require(afterBalance - beforeBalance == assets, "EulerEVault: wrong vault asset receipt");
    }
}
