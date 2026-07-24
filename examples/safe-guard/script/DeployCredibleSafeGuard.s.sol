// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {CredibleSafeGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";
import {ICredibleRegistry} from "credible-std/protection/safe/ICredibleRegistry.sol";

/// @notice Deploys a Credible Safe guard using Foundry's configured broadcast wallet.
contract DeployCredibleSafeGuard is Script {
    function run() external returns (CredibleSafeGuard guard) {
        address registry = vm.envAddress("CREDIBLE_REGISTRY");
        uint256 threshold = vm.envUint("FAIL_OPEN_BLOCK_THRESHOLD");

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
}
