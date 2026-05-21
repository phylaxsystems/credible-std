// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {VaultDemoAttack} from "../script/VaultDemoAttack.s.sol";
import {VaultDemoDeploy} from "../script/VaultDemoDeploy.s.sol";

contract VaultDemoScriptsTest is Test {
    function testDeployScriptFundsSafeAndVaults() public {
        VaultDemoDeploy deployScript = new VaultDemoDeploy();
        VaultDemoDeploy.Deployment memory deployment = deployScript.deployAndFund();

        assertEq(deployment.safe.balance, deployScript.SAFE_ETH_SEED());
        assertEq(deployment.asset.balanceOf(deployment.safe), 700 ether);
        assertEq(deployment.protectedVault.totalAssets(), deployScript.VAULT_ASSET_SEED());
        assertEq(deployment.protectedVault.totalSupply(), deployScript.VAULT_ASSET_SEED());
        assertEq(deployment.market.utilizationBps(), 9_950);
    }

    function testAttackScriptCompromisesOnlyUnprotectedVault() public {
        VaultDemoDeploy deployScript = new VaultDemoDeploy();
        VaultDemoDeploy.Deployment memory deployment = deployScript.deployAndFund();
        VaultDemoAttack attackScript = new VaultDemoAttack();

        VaultDemoAttack.AttackReport memory report = attackScript.compromiseUnprotectedVault(deployment);

        assertTrue(report.unprotectedMintCompromised);
        assertEq(report.unprotectedAssetsAfterMint, deployScript.VAULT_ASSET_SEED());
        assertEq(report.unprotectedSupplyAfterMint, deployScript.VAULT_ASSET_SEED() + 50 ether);

        deployScript.attachSharePriceAssertion(deployment);
        vm.expectRevert(bytes("VaultDemo: call-level share price drift"));
        attackScript.sendProtectedBadMint(deployment.asset, deployment.protectedVault, deployment.attacker);

        deployScript.attachConvertToAssetsOracleAssertion(deployment);
        vm.expectRevert(bytes("VaultDemo: convertToAssets deviated"));
        attackScript.sendProtectedBadDonation(deployment.asset, deployment.protectedVault, deployment.attacker);

        deployScript.attachInflowCircuitBreakerAssertion(deployment);
        vm.expectRevert(bytes("VaultDemo: cumulative inflow breaker tripped"));
        attackScript.sendProtectedLargeDeposit(deployment.asset, deployment.protectedVault, deployment.attacker);

        deployScript.attachOutflowCircuitBreakerAssertion(deployment);
        vm.expectRevert(bytes("VaultDemo: cumulative outflow breaker tripped"));
        attackScript.sendProtectedLargeWithdraw(deployment.protectedVault, deployment.safe);

        deployScript.attachCuratorMarketHealthAssertion(deployment);
        vm.expectRevert(bytes("VaultDemo: market utilization unhealthy"));
        attackScript.sendUnhealthyCuratorAllocation(
            deployment.curatorVault, address(deployment.market), deployment.curator
        );

        assertEq(deployment.protectedVault.totalAssets(), deployScript.VAULT_ASSET_SEED());
        assertEq(deployment.protectedVault.totalSupply(), deployScript.VAULT_ASSET_SEED());
    }
}
