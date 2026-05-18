// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IPreviewableVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
}

/// @notice For a single call, compare calldata, pre-call preview, return value, and emitted event.
/// @dev Protects against call-local dishonesty:
///      - a mutator returning a different amount than its immediate pre-call preview;
///      - event data disagreeing with calldata or return data;
///      - integrations reading a successful return/event while accounting used different values.
contract CallSandwichHonestyAssertion is Assertion {
    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertDepositWasHonest.selector, IPreviewableVault.deposit.selector);
    }

    function assertDepositWasHonest() external view {
        address vault = ph.getAssertionAdopter();
        PhEvm.TriggerContext memory ctx = ph.context();
        (uint256 assets, address receiver) = abi.decode(_stripSelector(ph.callinputAt(ctx.callStart)), (uint256, address));

        uint256 expectedShares = _readUintAt(
            vault, abi.encodeCall(IPreviewableVault.previewDeposit, (assets)), _preCall(ctx.callStart)
        );
        uint256 returnedShares = abi.decode(ph.callOutputAt(ctx.callStart), (uint256));

        // Failure scenario: the call charged one amount but minted shares inconsistent with its own preview.
        require(returnedShares == expectedShares, "return diverged from pre-call preview");

        PhEvm.LogQuery memory query = PhEvm.LogQuery({emitter: vault, signature: Deposit.selector});
        PhEvm.Log[] memory logs = ph.getLogsForCall(query, ctx.callEnd);

        // Failure scenario: off-chain/indexer-visible events do not faithfully describe the executed call.
        require(logs.length == 1, "missing deposit event");
        require(uint256(logs[0].topics[2]) == uint256(uint160(receiver)), "wrong receiver");
        (uint256 loggedAssets, uint256 loggedShares) = abi.decode(logs[0].data, (uint256, uint256));
        require(loggedAssets == assets && loggedShares == returnedShares, "event does not match call");
    }

    function _stripSelector(bytes memory input) private pure returns (bytes memory args) {
        require(input.length >= 4, "input too short");
        args = new bytes(input.length - 4);
        for (uint256 i; i < args.length; ++i) args[i] = input[i + 4];
    }
}
