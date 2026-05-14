// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IAccountingSurface {
    function totalAssets() external view returns (uint256);
    function liabilities() external view returns (uint256);
    function pendingWithdrawals() external view returns (uint256);
    function idleBalance() external view returns (uint256);
    function investedBalance() external view returns (uint256);
}

/// @notice Keeps aggregate accounting identities true after any transaction.
/// @dev Protects against accounting drift:
///      - asset buckets no longer sum to the reported aggregate;
///      - liabilities or queued withdrawals exceeding assets;
///      - stale internal accounting after deposits, withdrawals, fees, syncs, or strategy moves.
contract AccountingConservationAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertAccountingConserved.selector);
    }

    function assertAccountingConserved() external view {
        address target = ph.getAssertionAdopter();
        PhEvm.ForkId memory fork = _postTx();

        uint256 totalAssets = _readUintAt(target, abi.encodeCall(IAccountingSurface.totalAssets, ()), fork);
        uint256 liabilities = _readUintAt(target, abi.encodeCall(IAccountingSurface.liabilities, ()), fork);
        uint256 pendingWithdrawals =
            _readUintAt(target, abi.encodeCall(IAccountingSurface.pendingWithdrawals, ()), fork);
        uint256 idleBalance = _readUintAt(target, abi.encodeCall(IAccountingSurface.idleBalance, ()), fork);
        uint256 investedBalance = _readUintAt(target, abi.encodeCall(IAccountingSurface.investedBalance, ()), fork);

        // Failure scenario: funds moved between custody buckets but total accounting was not updated coherently.
        require(totalAssets == idleBalance + investedBalance, "asset buckets do not sum");

        // Failure scenario: the protocol reports more claims than it can cover with accounted assets.
        require(totalAssets >= liabilities + pendingWithdrawals, "assets do not cover claims");
    }
}
