// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {CredibleSafeGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";
import {ICredibleRegistry} from "credible-std/protection/safe/ICredibleRegistry.sol";

/// @notice Deploys a Credible Safe guard using Foundry's configured broadcast wallet.
contract DeployCredibleSafeGuard is Script {
    /// @notice Thrown when the configured registry address has no deployed code.
    /// @dev Catches the common footgun of a typo that resolves to an EOA: a codeless registry
    ///      makes every credibility probe fail open, so the guard would allow every transaction.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when a required registry read (isCredibleBlock / lastCredibleBlock) does not
    ///         return a single, well-formed 32-byte word.
    error RegistryReadFailed(address registry, string read);

    function run() external returns (CredibleSafeGuard guard) {
        address registry = vm.envAddress("CREDIBLE_REGISTRY");
        uint256 threshold = vm.envUint("FAIL_OPEN_BLOCK_THRESHOLD");

        // Validate the registry before broadcasting so a misconfigured (codeless or
        // non-responsive) registry is caught up front rather than silently deploying a
        // permanently-fail-open guard.
        validateRegistry(registry);

        vm.startBroadcast();
        guard = deploy(registry, threshold);
        vm.stopBroadcast();

        console2.log("Chain ID:", block.chainid);
        console2.log("Credible Safe guard:", address(guard));
        console2.log("Credible Registry:", registry);
        console2.log("Fail-open block threshold:", threshold);
    }

    function deploy(address registry, uint256 threshold) public returns (CredibleSafeGuard) {
        return new CredibleSafeGuard(ICredibleRegistry(registry), threshold);
    }

    /// @notice Asserts the registry has code and answers both reads the guard depends on.
    /// @dev Reverts with a descriptive error otherwise. Kept separate from {deploy} so the
    ///      constructor's own zero-address / zero-threshold validation is preserved for callers
    ///      that deploy against an in-memory mock.
    function validateRegistry(address registry) public view {
        if (registry.code.length == 0) revert RegistryHasNoCode(registry);

        (bool credibleOk, bytes memory credibleData) =
            registry.staticcall(abi.encodeCall(ICredibleRegistry.isCredibleBlock, (block.number)));
        if (!credibleOk || credibleData.length != 32) revert RegistryReadFailed(registry, "isCredibleBlock");

        (bool lastOk, bytes memory lastData) =
            registry.staticcall(abi.encodeCall(ICredibleRegistry.lastCredibleBlock, ()));
        if (!lastOk || lastData.length != 32) revert RegistryReadFailed(registry, "lastCredibleBlock");
    }
}
