// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {console2} from "forge-std/Script.sol";

import {SafeGuardBatch} from "./SafeGuardBatch.sol";

/// @notice Generates a Safe Transaction Builder JSON file for removing a legacy guard.
/// @custom:deprecated Use credible-registry/script/GenerateSafeGuardBatch.s.sol for installations.
/// @dev This script never broadcasts or signs. Import the generated file into Safe{Wallet}'s
///      Transaction Builder and submit it through the Safe's normal owner-confirmation flow.
contract GenerateSafeGuardBatch is SafeGuardBatch {
    function run() external returns (string memory json, string memory path) {
        Action action = parseAction(vm.envString("SAFE_GUARD_ACTION"));
        if (action == Action.Install) {
            revert("Deprecated: use credible-registry/script/GenerateSafeGuardBatch.s.sol for installations");
        }

        address safe = vm.envAddress("SAFE_ADDRESS");
        json = buildRemoveBatch(safe, block.chainid, vm.unixTime());
        path = outputPath(action);
        vm.createDir("safe-guard-output", true);
        vm.writeFile(path, json);

        console2.log("Safe Transaction Builder file:", path);
        console2.log("Chain ID:", block.chainid);
        console2.log("Safe:", safe);
        console2.log("Action: remove");
        console2.log("Guard:", address(0));
        console2.log("Import this JSON in Safe{Wallet} Transaction Builder and verify it before signing.");
    }
}
