// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {EulerERC4626CallSandwichAssertion} from "../src/EulerEVaultSandwichAssertion.sol";

contract MockEulerEVault {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    bool public breakPreview;
    bool public skipAccounting;
    ERC20Mock public immutable asset;
    mapping(address => uint256) public balanceOf;

    constructor(ERC20Mock asset_) {
        asset = asset_;
    }

    function setBreakPreview(bool enabled) external {
        breakPreview = enabled;
    }

    function setSkipAccounting(bool enabled) external {
        skipAccounting = enabled;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = breakPreview ? assets - 1 : assets;
        if (!skipAccounting) {
            asset.transferFrom(msg.sender, address(this), assets);
            balanceOf[receiver] += shares;
        }
        emit Deposit(msg.sender, receiver, assets, shares);
    }
}

contract EulerEVaultSandwichAssertionTest is Test, CredibleTest {
    MockEulerEVault internal vault;
    ERC20Mock internal asset;

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockEulerEVault(asset);
        asset.mint(address(this), 1_000 ether);
        asset.approve(address(vault), type(uint256).max);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(type(EulerERC4626CallSandwichAssertion).creationCode);
        cl.assertion(address(vault), createData, EulerERC4626CallSandwichAssertion.assertErc4626CallWasHonest.selector);
    }

    function testDepositMatchesPreCallPreview() public {
        _arm();
        vault.deposit(100 ether, address(this));
    }

    function testDepositReturnBelowPreviewTrips() public {
        vault.setBreakPreview(true);

        _arm();
        vm.expectRevert(bytes("EulerEVault: deposit return != pre-call preview"));
        vault.deposit(100 ether, address(this));
    }

    function testDepositReturnAndEventWithoutStateEffectsTrips() public {
        vault.setSkipAccounting(true);

        _arm();
        vm.expectRevert(bytes("EulerEVault: wrong receiver share mint"));
        vault.deposit(100 ether, address(this));
    }
}
