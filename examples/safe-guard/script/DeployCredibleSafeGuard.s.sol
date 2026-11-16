// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {CredibleSafeGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";
import {ICredibleRegistry} from "credible-std/protection/safe/ICredibleRegistry.sol";

/// @notice Deprecated legacy guard tooling; the broadcast entrypoint is disabled.
/// @custom:deprecated Use credible-registry/script/DeployCredibleSafeGuard.s.sol instead.
contract DeployCredibleSafeGuard is Script {
    /// @notice Thrown when the configured registry address has no deployed code.
    /// @dev Catches the common footgun of a typo that resolves to an EOA: a codeless registry
    ///      makes every credibility probe fail open, so the guard would allow every transaction.
    error RegistryHasNoCode(address registry);
    /// @notice Thrown when a required registry read (isCredibleBlock / lastCredibleBlock) does not
    ///         return a single, well-formed 32-byte word.
    error RegistryReadFailed(address registry, string read);

    function run() external pure returns (CredibleSafeGuard) {
        revert("Deprecated: use credible-registry/script/DeployCredibleSafeGuard.s.sol");
    }

    /// @dev Legacy helper retained for source compatibility and historical tests, not new deployments.
    function deploy(address registry, uint256 threshold, address protocolManager) public returns (CredibleSafeGuard) {
        console2.log("WARNING: deprecated guard; use credible-registry/src/CredibleSafeGuard.sol.");
        console2.log("The legacy registry ABI fails open against the current registry. Do not deploy this guard.");
        return new CredibleSafeGuard(ICredibleRegistry(registry), threshold, protocolManager);
    }

    /// @notice Asserts the registry has code and answers both reads the guard depends on.
    /// @dev Reverts with a descriptive error otherwise. Kept separate from {deploy} so the
    ///      constructor's own zero-address / zero-threshold validation is preserved for callers
    ///      that deploy against an in-memory mock.
    function validateRegistry(address registry) public view {
        if (registry.code.length == 0) revert RegistryHasNoCode(registry);

        // `isCredibleBlock` is a Solidity `bool`, so a well-formed answer is a canonical boolean
        // word (0 or 1). Reject any other 32-byte value (e.g. `abi.encode(uint256(2))`) here:
        // it passes the length check but the guard's runtime decode treats it as unreadable
        // (see CredibleSafeGuard._tryIsCredibleBlock's `value > 1` branch), which would otherwise
        // let a registry silently deploy a permanently-fail-open guard.
        (bool credibleOk, bytes memory credibleData) =
            registry.staticcall(abi.encodeCall(ICredibleRegistry.isCredibleBlock, (block.number)));
        if (!credibleOk || credibleData.length != 32 || abi.decode(credibleData, (uint256)) > 1) {
            revert RegistryReadFailed(registry, "isCredibleBlock");
        }

        (bool lastOk, bytes memory lastData) =
            registry.staticcall(abi.encodeCall(ICredibleRegistry.lastCredibleBlock, ()));
        if (!lastOk || lastData.length != 32) revert RegistryReadFailed(registry, "lastCredibleBlock");
    }
}
