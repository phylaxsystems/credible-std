// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {
    CuratorMarketHealthAssertion,
    VaultAssetsMatchSharePriceAssertion,
    VaultCircuitBreakerAssertion,
    VaultConvertToAssetsOracleSanityAssertion
} from "../src/VaultDemoAssertions.sol";
import {CuratorVaultDemo, VaultDemoMarket, VaultDemoOracle} from "../src/CuratorMarketDemo.sol";
import {VaultDemoToken, VulnerableERC4626Vault} from "../src/VulnerableERC4626Vault.sol";

contract VaultDemoTest is Test, CredibleTest {
    bytes4 internal constant ASSERT_PER_CALL_SHARE_PRICE = bytes4(keccak256("assertPerCallSharePrice()"));

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xBEEF);
    address internal curator = address(0xCAFE);

    VaultDemoToken internal asset;
    VulnerableERC4626Vault internal unprotectedVault;
    VulnerableERC4626Vault internal protectedVault;

    function setUp() public {
        asset = new VaultDemoToken("Demo USDM", "USDM");
        unprotectedVault = new VulnerableERC4626Vault(asset, "Unprotected Demo Vault", "uDEMO");
        protectedVault = new VulnerableERC4626Vault(asset, "Protected Demo Vault", "pDEMO");

        asset.mint(alice, 1_000 ether);
        asset.mint(attacker, 1_000 ether);
        asset.mint(curator, 1_000 ether);

        _seed(unprotectedVault, 100 ether);
        _seed(protectedVault, 100 ether);
    }

    function testBrokenMintCreatesUnbackedSharesWhenUnprotected() public {
        uint256 preAssets = unprotectedVault.totalAssets();
        uint256 preSupply = unprotectedVault.totalSupply();

        vm.prank(attacker);
        unprotectedVault.mint(50 ether, attacker);

        assertEq(unprotectedVault.totalAssets(), preAssets);
        assertEq(unprotectedVault.totalSupply(), preSupply + 50 ether);
    }

    function testBrokenMintDilutesSharePrice() public {
        uint256 preAssetsForOneShare = unprotectedVault.convertToAssets(1 ether);

        vm.prank(attacker);
        unprotectedVault.mint(50 ether, attacker);

        assertLt(unprotectedVault.convertToAssets(1 ether), preAssetsForOneShare);
    }

    function testAssetsMatchSharePriceBlocksBrokenMint() public {
        bytes memory createData = abi.encodePacked(
            type(VaultAssetsMatchSharePriceAssertion).creationCode, abi.encode(address(protectedVault), 0)
        );

        cl.assertion(address(protectedVault), createData, ASSERT_PER_CALL_SHARE_PRICE);

        vm.prank(attacker);
        vm.expectRevert(bytes("VaultDemo: call-level share price drift"));
        protectedVault.mint(50 ether, attacker);
    }

    function testConvertToAssetsOracleSanityBlocksDonationManipulation() public {
        vm.prank(attacker);
        asset.approve(address(protectedVault), 100 ether);

        bytes memory createData = abi.encodePacked(
            type(VaultConvertToAssetsOracleSanityAssertion).creationCode,
            abi.encode(address(protectedVault), 1 ether, 100)
        );

        cl.assertion(
            address(protectedVault),
            createData,
            VaultConvertToAssetsOracleSanityAssertion.assertConvertToAssetsOracleSanity.selector
        );

        vm.prank(attacker);
        vm.expectRevert(bytes("VaultDemo: convertToAssets deviated"));
        protectedVault.donateAssets(100 ether);
    }

    function testCuratorAllocationBlockedWhenMarketUtilizationIsUnhealthy() public {
        VaultDemoOracle oracle = new VaultDemoOracle(1 ether);
        VaultDemoMarket market = new VaultDemoMarket(asset, oracle);
        CuratorVaultDemo vault = new CuratorVaultDemo(asset, curator);

        asset.mint(address(vault), 100 ether);
        _seedMarket(market, 100 ether);
        market.setBorrowed(99.5 ether);

        assertGt(market.utilizationBps(), 9_900);

        bytes memory createData =
            abi.encodePacked(type(CuratorMarketHealthAssertion).creationCode, abi.encode(address(vault), 9_900, 100));

        cl.assertion(address(vault), createData, CuratorMarketHealthAssertion.assertTargetMarketHealthy.selector);

        vm.prank(curator);
        vm.expectRevert(bytes("VaultDemo: market utilization unhealthy"));
        vault.allocate(address(market), 10 ether);
    }

    function testCircuitBreakerBlocksDepositAboveTwentyFivePercentInSixHours() public {
        vm.prank(attacker);
        asset.approve(address(protectedVault), 50 ether);

        bytes memory createData = abi.encodePacked(
            type(VaultCircuitBreakerAssertion).creationCode, abi.encode(address(protectedVault), address(asset))
        );

        cl.assertion(address(protectedVault), createData, VaultCircuitBreakerAssertion.assertCumulativeInflow.selector);

        vm.prank(attacker);
        vm.expectRevert(bytes("VaultDemo: cumulative inflow breaker tripped"));
        protectedVault.deposit(50 ether, attacker);
    }

    function testCircuitBreakerBlocksWithdrawAboveTwentyFivePercentInTwentyFourHours() public {
        bytes memory createData = abi.encodePacked(
            type(VaultCircuitBreakerAssertion).creationCode, abi.encode(address(protectedVault), address(asset))
        );

        cl.assertion(address(protectedVault), createData, VaultCircuitBreakerAssertion.assertCumulativeOutflow.selector);

        vm.prank(alice);
        vm.expectRevert(bytes("VaultDemo: cumulative outflow breaker tripped"));
        protectedVault.withdraw(50 ether, alice, alice);
    }

    function _seed(VulnerableERC4626Vault vault, uint256 assets) internal {
        vm.startPrank(alice);
        asset.approve(address(vault), assets);
        vault.deposit(assets, alice);
        vm.stopPrank();
    }

    function _seedMarket(VaultDemoMarket market, uint256 assets) internal {
        vm.startPrank(alice);
        asset.approve(address(market), assets);
        market.deposit(assets);
        vm.stopPrank();
    }
}
