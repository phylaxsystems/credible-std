// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console2} from "forge-std/Script.sol";

import {SafeGuardBatch} from "./SafeGuardBatch.sol";

/// @notice Generates a Safe Transaction Builder JSON file for installing or removing a guard.
/// @dev This script never broadcasts or signs. Import the generated file into Safe{Wallet}'s
///      Transaction Builder and submit it through the Safe's normal owner-confirmation flow.
contract GenerateSafeGuardBatch is SafeGuardBatch {
    function run() external returns (string memory json, string memory path) {
        address safe = vm.envAddress("SAFE_ADDRESS");
        Action action = parseAction(vm.envString("SAFE_GUARD_ACTION"));
        address guard = vm.envOr("CREDIBLE_SAFE_GUARD", address(0));
        uint256 createdAt = vm.unixTime();

        if (action == Action.Install) {
            json = buildInstallBatch(safe, guard, block.chainid, createdAt);
        } else {
            json = buildRemoveBatch(safe, block.chainid, createdAt);
        }

        path = outputPath(action);
        vm.createDir("safe-guard-output", true);
        vm.writeFile(path, json);

        console2.log("Safe Transaction Builder file:", path);
        console2.log("Chain ID:", block.chainid);
        console2.log("Safe:", safe);
        console2.log("Action:", action == Action.Install ? "install" : "remove");
        console2.log("Guard:", action == Action.Install ? guard : address(0));
        console2.log("Import this JSON in Safe{Wallet} Transaction Builder and verify it before signing.");
    }
}
