// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {ERC4626BaseAssertion} from "../../../src/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626SharePriceAssertion} from "../../../src/protection/vault/ERC4626SharePriceAssertion.sol";

contract MockBoundedSharePriceVault {
    address public asset;
    uint256 public totalAssets = 100 ether;
    uint256 public totalSupply = 100 ether;

    constructor(address asset_) {
        asset = asset_;
    }

    function touch() external {}
}

contract ERC4626SharePriceAssertionHarness is ERC4626SharePriceAssertion {
    constructor(address vault_, address asset_) ERC4626BaseAssertion(vault_, asset_) ERC4626SharePriceAssertion(0) {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        _registerBoundedSharePriceTriggers();
    }
}

contract ERC4626SharePriceAssertionTest is Test, CredibleTest {
    address internal asset = makeAddr("asset");
    address internal otherAsset = makeAddr("otherAsset");

    MockBoundedSharePriceVault internal vault;

    function setUp() public {
        vault = new MockBoundedSharePriceVault(asset);
    }

    function testBoundedSharePriceChecksConfiguredVaultAndAsset() public {
        _arm(address(vault), address(vault), asset);

        vault.touch();
    }

    function testBoundedSharePriceRejectsWrongAdopter() public {
        MockBoundedSharePriceVault otherVault = new MockBoundedSharePriceVault(asset);
        _arm(address(otherVault), address(vault), asset);

        vm.expectRevert(bytes("ERC4626: configured vault is not adopter"));
        otherVault.touch();
    }

    function testBoundedSharePriceRejectsWrongAsset() public {
        _arm(address(vault), address(vault), otherAsset);

        vm.expectRevert(bytes("ERC4626: asset mismatch"));
        vault.touch();
    }

    function _arm(address adopter, address configuredVault, address configuredAsset) internal {
        bytes memory createData = abi.encodePacked(
            type(ERC4626SharePriceAssertionHarness).creationCode, abi.encode(configuredVault, configuredAsset)
        );
        cl.assertion(adopter, createData, ERC4626SharePriceAssertion.assertSharePriceEnvelopeBounded.selector);
    }
}
