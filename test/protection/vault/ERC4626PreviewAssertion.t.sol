// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {ERC4626BaseAssertion} from "../../../src/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626PreviewAssertion} from "../../../src/protection/vault/ERC4626PreviewAssertion.sol";
import {MetaMorphoVaultAssertion} from "../../../src/protection/vault/examples/MetaMorphoVaultAssertion.sol";
import {LlamaLendVaultAssertion} from "../../../examples/curve/src/LlamaLendVaultAssertion.sol";
import {SparkVaultAssertion} from "../../../examples/spark/src/SparkVaultAssertion.sol";

contract PreviewAssetCustodian {
    function release(ERC20Mock token, address receiver, uint256 amount) external {
        token.transfer(receiver, amount);
    }
}

contract PreviewEffectsVault is ERC20 {
    ERC20Mock public immutable underlying;
    address public immutable custodian;
    bool public skipShares;
    bool public skipAssets;
    address public paymentSource;
    address public extraChargeRecipient;

    constructor(ERC20Mock underlying_, address custodian_) ERC20("Vault Share", "VS") {
        underlying = underlying_;
        custodian = custodian_ == address(0) ? address(this) : custodian_;
    }

    function setFaults(bool skipShares_, bool skipAssets_) external {
        skipShares = skipShares_;
        skipAssets = skipAssets_;
    }

    function setPaymentFaults(address paymentSource_, address extraChargeRecipient_) external {
        paymentSource = paymentSource_;
        extraChargeRecipient = extraChargeRecipient_;
    }

    function asset() external view returns (address) {
        return address(underlying);
    }

    function totalAssets() external view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewMint(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (!skipAssets) _collect(assets);
        if (!skipShares) _mint(receiver, assets);
        return assets;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        if (!skipAssets) _collect(shares);
        if (!skipShares) _mint(receiver, shares);
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (!skipShares) _burn(owner, assets);
        if (!skipAssets) _release(receiver, assets);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (!skipShares) _burn(owner, shares);
        if (!skipAssets) _release(receiver, shares);
        return shares;
    }

    function _release(address receiver, uint256 amount) internal {
        if (custodian == address(this)) underlying.transfer(receiver, amount);
        else PreviewAssetCustodian(custodian).release(underlying, receiver, amount);
    }

    function _collect(uint256 amount) internal {
        address payer = paymentSource == address(0) ? msg.sender : paymentSource;
        underlying.transferFrom(payer, custodian, amount);
        if (extraChargeRecipient != address(0)) underlying.transferFrom(payer, extraChargeRecipient, amount);
    }
}

contract PreviewEffectsAssertion is ERC4626PreviewAssertion {
    address internal immutable custody;

    constructor(address vault_, address asset_, address custody_) ERC4626BaseAssertion(vault_, asset_) {
        custody = custody_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        _registerPreviewTriggers();
    }

    function _maxPreviewDeviation() internal pure override returns (uint256) {
        return 0;
    }

    function _assetCustodyAccount() internal view override returns (address) {
        return custody;
    }
}

contract PreviewMetaMorphoHarness is MetaMorphoVaultAssertion {
    constructor(address vault_, address asset_) MetaMorphoVaultAssertion(vault_, asset_) {}

    function triggers() external view override {
        _registerPreviewTriggers();
    }
}

contract PreviewSparkHarness is SparkVaultAssertion {
    constructor(address vault_, address asset_) SparkVaultAssertion(vault_, asset_) {}

    function triggers() external view override {
        _registerPreviewTriggers();
    }
}

contract PreviewLlamaHarness is LlamaLendVaultAssertion {
    constructor(address vault_, address asset_, address controller_)
        LlamaLendVaultAssertion(vault_, asset_, controller_)
    {}

    function triggers() external view override {
        _registerPreviewTriggers();
    }
}

contract ERC4626PreviewAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    PreviewEffectsVault internal vault;
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new PreviewEffectsVault(asset, address(0));
        asset.mint(address(this), 1_000 ether);
        asset.approve(address(vault), type(uint256).max);
    }

    function _arm(bytes4 selector) internal {
        bytes memory createData = abi.encodePacked(
            type(PreviewEffectsAssertion).creationCode, abi.encode(address(vault), address(asset), vault.custodian())
        );
        cl.assertion(address(vault), createData, selector);
    }

    function testDepositProvesAllStateEffects() public {
        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vault.deposit(100 ether, receiver);
    }

    function testMintProvesAllStateEffects() public {
        _arm(ERC4626PreviewAssertion.assertMintPreview.selector);
        vault.mint(100 ether, receiver);
    }

    function testWithdrawProvesAllStateEffects() public {
        vault.deposit(100 ether, address(this));
        _arm(ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vault.withdraw(40 ether, receiver, address(this));
    }

    function testRedeemProvesAllStateEffects() public {
        vault.deposit(100 ether, address(this));
        _arm(ERC4626PreviewAssertion.assertRedeemPreview.selector);
        vault.redeem(40 ether, receiver, address(this));
    }

    function testDepositSupportsExternalAssetCustody() public {
        PreviewAssetCustodian externalCustodian = new PreviewAssetCustodian();
        vault = new PreviewEffectsVault(asset, address(externalCustodian));
        asset.approve(address(vault), type(uint256).max);

        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vault.deposit(100 ether, receiver);
        assertEq(asset.balanceOf(address(externalCustodian)), 100 ether);
    }

    function testWithdrawSupportsExternalAssetCustody() public {
        PreviewAssetCustodian externalCustodian = new PreviewAssetCustodian();
        vault = new PreviewEffectsVault(asset, address(externalCustodian));
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100 ether, address(this));

        _arm(ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vault.withdraw(40 ether, receiver, address(this));
        assertEq(asset.balanceOf(address(externalCustodian)), 60 ether);
    }

    function testFavorableReturnWithoutSharesTrips() public {
        vault.setFaults(true, true);
        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit receiver shares mismatch"));
        vault.deposit(100 ether, receiver);
    }

    function testMissingShareEffectTrips() public {
        vault.setFaults(true, false);
        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit receiver shares mismatch"));
        vault.deposit(100 ether, receiver);
    }

    function testMissingAssetEffectTrips() public {
        vault.setFaults(false, true);
        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit asset payment mismatch"));
        vault.deposit(100 ether, receiver);
    }

    function testDepositOverchargeTripsEvenWhenCustodyReceivesExpectedAmount() public {
        vault.setPaymentFaults(address(0), makeAddr("diversion"));
        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit payer assets mismatch"));
        vault.deposit(100 ether, receiver);
    }

    function testDepositWrongPayerTrips() public {
        address wrongPayer = makeAddr("wrongPayer");
        asset.mint(wrongPayer, 100 ether);
        vm.prank(wrongPayer);
        asset.approve(address(vault), type(uint256).max);
        vault.setPaymentFaults(wrongPayer, address(0));
        _arm(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit payer assets mismatch"));
        vault.deposit(100 ether, receiver);
    }

    function testMintMissingShareEffectTrips() public {
        vault.setFaults(true, false);
        _arm(ERC4626PreviewAssertion.assertMintPreview.selector);
        vm.expectRevert(bytes("ERC4626: mint receiver shares mismatch"));
        vault.mint(100 ether, receiver);
    }

    function testMintMissingAssetEffectTrips() public {
        vault.setFaults(false, true);
        _arm(ERC4626PreviewAssertion.assertMintPreview.selector);
        vm.expectRevert(bytes("ERC4626: mint asset payment mismatch"));
        vault.mint(100 ether, receiver);
    }

    function testWithdrawMissingShareEffectTrips() public {
        vault.deposit(100 ether, address(this));
        vault.setFaults(true, false);
        _arm(ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vm.expectRevert(bytes("ERC4626: withdraw owner shares mismatch"));
        vault.withdraw(40 ether, receiver, address(this));
    }

    function testWithdrawMissingAssetEffectTrips() public {
        vault.deposit(100 ether, address(this));
        vault.setFaults(false, true);
        _arm(ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vm.expectRevert(bytes("ERC4626: withdraw vault assets mismatch"));
        vault.withdraw(40 ether, receiver, address(this));
    }

    function testRedeemMissingShareEffectTrips() public {
        vault.deposit(100 ether, address(this));
        vault.setFaults(true, false);
        _arm(ERC4626PreviewAssertion.assertRedeemPreview.selector);
        vm.expectRevert(bytes("ERC4626: redeem owner shares mismatch"));
        vault.redeem(40 ether, receiver, address(this));
    }

    function testRedeemMissingAssetEffectTrips() public {
        vault.deposit(100 ether, address(this));
        vault.setFaults(false, true);
        _arm(ERC4626PreviewAssertion.assertRedeemPreview.selector);
        vm.expectRevert(bytes("ERC4626: redeem vault assets mismatch"));
        vault.redeem(40 ether, receiver, address(this));
    }

    function testWithdrawAllowsReceiverToEqualCustody() public {
        vault.deposit(100 ether, address(this));
        _arm(ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vault.withdraw(40 ether, address(vault), address(this));
    }

    function testRedeemAllowsReceiverToEqualCustody() public {
        vault.deposit(100 ether, address(this));
        _arm(ERC4626PreviewAssertion.assertRedeemPreview.selector);
        vault.redeem(40 ether, address(vault), address(this));
    }

    function testMetaMorphoAdapterHonestAndIncorrectEffects() public {
        bytes memory createData =
            abi.encodePacked(type(PreviewMetaMorphoHarness).creationCode, abi.encode(address(vault), address(asset)));
        cl.assertion(address(vault), createData, ERC4626PreviewAssertion.assertDepositPreview.selector);
        vault.deposit(10 ether, receiver);

        vault.setFaults(false, true);
        cl.assertion(address(vault), createData, ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit asset payment mismatch"));
        vault.deposit(10 ether, receiver);
    }

    function testSparkAdapterHonestAndIncorrectEffects() public {
        bytes memory createData =
            abi.encodePacked(type(PreviewSparkHarness).creationCode, abi.encode(address(vault), address(asset)));
        cl.assertion(address(vault), createData, ERC4626PreviewAssertion.assertMintPreview.selector);
        vault.mint(10 ether, receiver);

        vault.setFaults(true, false);
        cl.assertion(address(vault), createData, ERC4626PreviewAssertion.assertMintPreview.selector);
        vm.expectRevert(bytes("ERC4626: mint receiver shares mismatch"));
        vault.mint(10 ether, receiver);
    }

    function testLlamaAdapterUsesControllerCustodyForHonestAndIncorrectEffects() public {
        PreviewAssetCustodian controller = new PreviewAssetCustodian();
        vault = new PreviewEffectsVault(asset, address(controller));
        asset.approve(address(vault), type(uint256).max);
        bytes memory createData = abi.encodePacked(
            type(PreviewLlamaHarness).creationCode, abi.encode(address(vault), address(asset), address(controller))
        );
        cl.assertion(address(vault), createData, ERC4626PreviewAssertion.assertDepositPreview.selector);
        vault.deposit(10 ether, receiver);
        assertEq(asset.balanceOf(address(controller)), 10 ether);

        vault.setFaults(false, true);
        cl.assertion(address(vault), createData, ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.expectRevert(bytes("ERC4626: deposit asset payment mismatch"));
        vault.deposit(10 ether, receiver);
    }
}
