// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IConfigurableVault {
    function initialized() external view returns (bool);
    function manager() external view returns (address);
    function slasher() external view returns (address);
    function epochDuration() external view returns (uint256);
    function vetoDuration() external view returns (uint256);
}

/// @notice Whole-state config sanity for initialization, wiring, and timing parameters.
/// @dev Protects against deployment and governance footguns:
///      - a vault left partially initialized;
///      - required manager/slasher links left unset or accidentally cleared;
///      - epoch or veto timing that makes exits, slashing, or veto execution unsafe.
contract ConfigurationGuardAssertion is Assertion {
    uint256 public constant MIN_EPOCH = 1 days;
    uint256 public constant MAX_EPOCH = 30 days;

    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertConfigurationSane.selector);
    }

    function assertConfigurationSane() external view {
        address vault = ph.getAssertionAdopter();
        PhEvm.ForkId memory fork = _postTx();

        bool initialized = abi.decode(_viewAt(vault, abi.encodeCall(IConfigurableVault.initialized, ()), fork), (bool));
        address manager = _readAddressAt(vault, abi.encodeCall(IConfigurableVault.manager, ()), fork);
        address slasher = _readAddressAt(vault, abi.encodeCall(IConfigurableVault.slasher, ()), fork);
        uint256 epoch = _readUintAt(vault, abi.encodeCall(IConfigurableVault.epochDuration, ()), fork);
        uint256 veto = _readUintAt(vault, abi.encodeCall(IConfigurableVault.vetoDuration, ()), fork);

        // Failure scenario: setup transaction exits with a half-wired deployment.
        require(initialized, "not initialized");
        require(manager != address(0), "manager missing");
        require(slasher != address(0), "slasher missing");

        // Failure scenario: governance changes timing parameters outside the system's operating envelope.
        require(epoch >= MIN_EPOCH && epoch <= MAX_EPOCH, "epoch out of bounds");
        require(veto < epoch, "veto must fit inside epoch");
    }
}
