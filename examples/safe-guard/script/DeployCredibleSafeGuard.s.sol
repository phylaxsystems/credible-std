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
    /// @notice Thrown when the registry reports a block that cannot yet have been credible.
    error RegistryLastCredibleBlockInFuture(address registry, uint256 reportedBlock, uint256 currentBlock);

    uint256 internal constant REGISTRY_READ_GAS_LIMIT = 50_000;

    function run() external returns (CredibleSafeGuard guard) {
        address registry = vm.envAddress("CREDIBLE_REGISTRY");
        uint256 threshold = vm.envUint("FAIL_OPEN_BLOCK_THRESHOLD");
        address protocolManager = vm.envAddress("INITIAL_PROTOCOL_MANAGER");

        // Validate the registry before broadcasting so a misconfigured (codeless or
        // non-responsive) registry is caught up front rather than silently deploying a
        // permanently-fail-open guard.
        validateRegistry(registry);

        vm.startBroadcast();
        guard = deploy(registry, threshold, protocolManager);
        vm.stopBroadcast();

        console2.log("Chain ID:", block.chainid);
        console2.log("Credible Safe guard:", address(guard));
        console2.log("Credible Registry:", registry);
        console2.log("Fail-open block threshold:", threshold);
        console2.log("Initial protocol manager:", protocolManager);
    }

    function deploy(address registry, uint256 threshold, address protocolManager)
        public
        returns (CredibleSafeGuard)
    {
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
        (bool credibleOk, uint256 credibleWord) =
            _boundedRegistryRead(registry, abi.encodeCall(ICredibleRegistry.isCredibleBlock, (block.number)));
        if (!credibleOk || credibleWord > 1) {
            revert RegistryReadFailed(registry, "isCredibleBlock");
        }

        (bool lastOk, uint256 lastCredibleBlock) =
            _boundedRegistryRead(registry, abi.encodeCall(ICredibleRegistry.lastCredibleBlock, ()));
        if (!lastOk) revert RegistryReadFailed(registry, "lastCredibleBlock");
        if (lastCredibleBlock > block.number) {
            revert RegistryLastCredibleBlockInFuture(registry, lastCredibleBlock, block.number);
        }
    }

    /// @dev Mirrors the guard's runtime boundary: 50k gas, exactly one return word, and no
    ///      unbounded returndata allocation. Deployment rejects failures; runtime fails open.
    function _boundedRegistryRead(address registry, bytes memory callData)
        internal
        view
        returns (bool readable, uint256 value)
    {
        assembly ("memory-safe") {
            readable := staticcall(
                REGISTRY_READ_GAS_LIMIT,
                registry,
                add(callData, 0x20),
                mload(callData),
                0x00,
                0x20
            )
            readable := and(readable, eq(returndatasize(), 0x20))
            value := mload(0x00)
        }
    }
}
