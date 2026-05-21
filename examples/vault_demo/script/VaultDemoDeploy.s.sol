// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    CuratorMarketHealthAssertion,
    VaultAssetsMatchSharePriceAssertion,
    VaultCircuitBreakerAssertion,
    VaultConvertToAssetsOracleSanityAssertion
} from "../src/VaultDemoAssertions.sol";
import {CuratorVaultDemo, VaultDemoMarket, VaultDemoOracle} from "../src/CuratorMarketDemo.sol";
import {VaultDemoToken, VulnerableERC4626Vault} from "../src/VulnerableERC4626Vault.sol";

contract VaultDemoDeploy is Script, CredibleTest {
    bytes4 internal constant ASSERT_PER_CALL_SHARE_PRICE = bytes4(keccak256("assertPerCallSharePrice()"));

    uint256 public constant SAFE_ETH_SEED = 1 wei;
    uint256 public constant ACTOR_TOKEN_SEED = 1_000 ether;
    uint256 public constant VAULT_ASSET_SEED = 100 ether;
    uint256 public constant CURATOR_VAULT_SEED = 100 ether;
    uint256 public constant MARKET_ASSET_SEED = 100 ether;
    uint256 public constant DEPLOYER_TOKEN_SEED = 1_000 ether;

    address public constant SAFE = address(0x5AFE);
    address public constant ATTACKER = address(0xBEEF);
    address public constant CURATOR = address(0xCAFE);

    struct Deployment {
        VaultDemoToken asset;
        VulnerableERC4626Vault unprotectedVault;
        VulnerableERC4626Vault protectedVault;
        VaultDemoOracle oracle;
        VaultDemoMarket market;
        CuratorVaultDemo curatorVault;
        address safe;
        address attacker;
        address curator;
    }

    function run() external {
        address deployer = _broadcastSender();
        address safe = vm.envOr("VAULT_DEMO_SAFE", deployer);
        Deployment memory deployment;

        vm.startBroadcast();
        deployment = deployAndFundForBroadcast(safe, deployer);
        vm.stopBroadcast();

        vm.broadcast();
        new SafeWeiFundingTx{value: SAFE_ETH_SEED}(safe);

        _logDeployment(deployment);
    }

    function deployAndFund() public returns (Deployment memory deployment) {
        deployment.safe = SAFE;
        deployment.attacker = ATTACKER;
        deployment.curator = CURATOR;

        deployment.asset = new VaultDemoToken("Demo USDM", "USDM");
        deployment.unprotectedVault = new VulnerableERC4626Vault(deployment.asset, "Unprotected Demo Vault", "uDEMO");
        deployment.protectedVault = new VulnerableERC4626Vault(deployment.asset, "Protected Demo Vault", "pDEMO");
        deployment.oracle = new VaultDemoOracle(1 ether);
        deployment.market = new VaultDemoMarket(deployment.asset, deployment.oracle);
        deployment.curatorVault = new CuratorVaultDemo(deployment.asset, deployment.curator);

        _fund(deployment);
        _seedVault(deployment.asset, deployment.unprotectedVault, deployment.safe, VAULT_ASSET_SEED);
        _seedVault(deployment.asset, deployment.protectedVault, deployment.safe, VAULT_ASSET_SEED);
        _seedMarket(deployment.asset, deployment.market, deployment.safe, MARKET_ASSET_SEED);
        deployment.market.setBorrowed(99.5 ether);
    }

    function deployAndFundForBroadcast(address safe, address deployer) public returns (Deployment memory deployment) {
        require(safe != address(0), "VaultDemo: safe is zero");
        require(deployer != address(0), "VaultDemo: deployer is zero");

        deployment.safe = safe;
        deployment.attacker = deployer;
        deployment.curator = deployer;

        deployment.asset = new VaultDemoToken("Demo USDM", "USDM");
        deployment.unprotectedVault = new VulnerableERC4626Vault(deployment.asset, "Unprotected Demo Vault", "uDEMO");
        deployment.protectedVault = new VulnerableERC4626Vault(deployment.asset, "Protected Demo Vault", "pDEMO");
        deployment.oracle = new VaultDemoOracle(1 ether);
        deployment.market = new VaultDemoMarket(deployment.asset, deployment.oracle);
        deployment.curatorVault = new CuratorVaultDemo(deployment.asset, deployment.curator);

        _fundForBroadcast(deployment, deployer);
        _seedVaultFromDeployer(deployment.asset, deployment.unprotectedVault, deployment.safe, VAULT_ASSET_SEED);
        _seedVaultFromDeployer(deployment.asset, deployment.protectedVault, deployment.safe, VAULT_ASSET_SEED);
        _seedMarketFromDeployer(deployment.asset, deployment.market, MARKET_ASSET_SEED);
        deployment.market.setBorrowed(99.5 ether);
    }

    function _fund(Deployment memory deployment) internal {
        vm.deal(deployment.safe, SAFE_ETH_SEED);
        vm.deal(deployment.attacker, SAFE_ETH_SEED);
        vm.deal(deployment.curator, SAFE_ETH_SEED);

        deployment.asset.mint(deployment.safe, ACTOR_TOKEN_SEED);
        deployment.asset.mint(deployment.attacker, ACTOR_TOKEN_SEED);
        deployment.asset.mint(deployment.curator, ACTOR_TOKEN_SEED);
        deployment.asset.mint(address(deployment.curatorVault), CURATOR_VAULT_SEED);
    }

    function _fundForBroadcast(Deployment memory deployment, address deployer) internal {
        deployment.asset.mint(deployer, DEPLOYER_TOKEN_SEED);
        deployment.asset.mint(deployment.safe, ACTOR_TOKEN_SEED);
        deployment.asset.mint(deployment.attacker, ACTOR_TOKEN_SEED);
        deployment.asset.mint(deployment.curator, ACTOR_TOKEN_SEED);
        deployment.asset.mint(address(deployment.curatorVault), CURATOR_VAULT_SEED);
    }

    function _seedVault(VaultDemoToken asset, VulnerableERC4626Vault vault, address safe, uint256 assets) internal {
        vm.startPrank(safe);
        asset.approve(address(vault), assets);
        vault.deposit(assets, safe);
        vm.stopPrank();
    }

    function _seedVaultFromDeployer(
        VaultDemoToken asset,
        VulnerableERC4626Vault vault,
        address receiver,
        uint256 assets
    ) internal {
        asset.approve(address(vault), assets);
        vault.deposit(assets, receiver);
    }

    function _seedMarket(VaultDemoToken asset, VaultDemoMarket market, address safe, uint256 assets) internal {
        vm.startPrank(safe);
        asset.approve(address(market), assets);
        market.deposit(assets);
        vm.stopPrank();
    }

    function _seedMarketFromDeployer(VaultDemoToken asset, VaultDemoMarket market, uint256 assets) internal {
        asset.approve(address(market), assets);
        market.deposit(assets);
    }

    function attachSharePriceAssertion(Deployment memory deployment) public {
        bytes memory sharePriceCreateData = abi.encodePacked(
            type(VaultAssetsMatchSharePriceAssertion).creationCode, abi.encode(address(deployment.protectedVault), 0)
        );
        cl.assertion(address(deployment.protectedVault), sharePriceCreateData, ASSERT_PER_CALL_SHARE_PRICE);
    }

    function attachConvertToAssetsOracleAssertion(Deployment memory deployment) public {
        bytes memory oracleCreateData = abi.encodePacked(
            type(VaultConvertToAssetsOracleSanityAssertion).creationCode,
            abi.encode(address(deployment.protectedVault), 1 ether, 100)
        );
        cl.assertion(
            address(deployment.protectedVault),
            oracleCreateData,
            VaultConvertToAssetsOracleSanityAssertion.assertConvertToAssetsOracleSanity.selector
        );
    }

    function attachInflowCircuitBreakerAssertion(Deployment memory deployment) public {
        bytes memory inflowBreakerCreateData = abi.encodePacked(
            type(VaultCircuitBreakerAssertion).creationCode,
            abi.encode(address(deployment.protectedVault), address(deployment.asset))
        );
        cl.assertion(
            address(deployment.protectedVault),
            inflowBreakerCreateData,
            VaultCircuitBreakerAssertion.assertCumulativeInflow.selector
        );
    }

    function attachOutflowCircuitBreakerAssertion(Deployment memory deployment) public {
        bytes memory outflowBreakerCreateData = abi.encodePacked(
            type(VaultCircuitBreakerAssertion).creationCode,
            abi.encode(address(deployment.protectedVault), address(deployment.asset))
        );
        cl.assertion(
            address(deployment.protectedVault),
            outflowBreakerCreateData,
            VaultCircuitBreakerAssertion.assertCumulativeOutflow.selector
        );
    }

    function attachCuratorMarketHealthAssertion(Deployment memory deployment) public {
        bytes memory curatorCreateData = abi.encodePacked(
            type(CuratorMarketHealthAssertion).creationCode, abi.encode(address(deployment.curatorVault), 9_900, 100)
        );
        cl.assertion(
            address(deployment.curatorVault),
            curatorCreateData,
            CuratorMarketHealthAssertion.assertTargetMarketHealthy.selector
        );
    }

    function _logDeployment(Deployment memory deployment) internal view {
        console2.log("safe", deployment.safe);
        console2.log("attacker", deployment.attacker);
        console2.log("curator", deployment.curator);
        console2.log("asset", address(deployment.asset));
        console2.log("unprotectedVault", address(deployment.unprotectedVault));
        console2.log("protectedVault", address(deployment.protectedVault));
        console2.log("oracle", address(deployment.oracle));
        console2.log("market", address(deployment.market));
        console2.log("curatorVault", address(deployment.curatorVault));
        console2.log("safeEthBalance", deployment.safe.balance);
        console2.log("safeAssetBalance", deployment.asset.balanceOf(deployment.safe));
        console2.log("protectedVaultAssets", deployment.protectedVault.totalAssets());
    }

    function _broadcastSender() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        if (wallets.length != 0) return wallets[0];
        return vm.envAddress("VAULT_DEMO_SENDER");
    }
}

contract SafeWeiFundingTx {
    constructor(address safe) payable {
        (bool ok,) = safe.call{value: msg.value}("");
        require(ok, "VaultDemo: safe funding failed");
    }
}
