// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {ERC4626BaseAssertion} from "../../../src/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626PreviewAssertion} from "../../../src/protection/vault/ERC4626PreviewAssertion.sol";

contract PreviewEffectsVault is ERC20 {
    ERC20Mock public immutable underlying;
    bool public skipShares;
    bool public skipAssets;

    constructor(ERC20Mock underlying_) ERC20("Vault Share", "VS") {
        underlying = underlying_;
    }

    function setFaults(bool skipShares_, bool skipAssets_) external {
        skipShares = skipShares_;
        skipAssets = skipAssets_;
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
        if (!skipAssets) underlying.transferFrom(msg.sender, address(this), assets);
        if (!skipShares) _mint(receiver, assets);
        return assets;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        if (!skipAssets) underlying.transferFrom(msg.sender, address(this), shares);
        if (!skipShares) _mint(receiver, shares);
        return shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        if (!skipShares) _burn(owner, assets);
        if (!skipAssets) underlying.transfer(receiver, assets);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (!skipShares) _burn(owner, shares);
        if (!skipAssets) underlying.transfer(receiver, shares);
        return shares;
    }
}

contract PreviewEffectsAssertion is ERC4626PreviewAssertion {
    constructor(address vault_, address asset_) ERC4626BaseAssertion(vault_, asset_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }
    function triggers() external view override {
        _registerPreviewTriggers();
    }

    function _maxPreviewDeviation() internal pure override returns (uint256) {
        return 0;
    }
}

contract ERC4626PreviewAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    PreviewEffectsVault internal vault;
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new PreviewEffectsVault(asset);
        asset.mint(address(this), 1_000 ether);
        asset.approve(address(vault), type(uint256).max);
    }

    function _arm(bytes4 selector) internal {
        bytes memory createData =
            abi.encodePacked(type(PreviewEffectsAssertion).creationCode, abi.encode(address(vault), address(asset)));
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
}
