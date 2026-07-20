// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SparkVaultAssertion} from "../src/SparkVaultAssertion.sol";

contract MockSparkVault {
    ERC20Mock public immutable assetToken;
    uint256 public totalSupply = 100 ether;
    uint256 public totalAssets = 100 ether;
    uint256 public chi = 1e27;
    uint256 public rho = 1;
    uint256 public vsr = 1;
    bool public breakOutstanding;

    constructor(ERC20Mock assetToken_) {
        assetToken = assetToken_;
    }

    function setBreakOutstanding(bool enabled) external {
        breakOutstanding = enabled;
    }

    function nowChi() external view returns (uint256) {
        return chi;
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function assetsOutstanding() external view returns (uint256) {
        if (breakOutstanding) return 0;
        uint256 liquidity = assetToken.balanceOf(address(this));
        return totalAssets > liquidity ? totalAssets - liquidity : 0;
    }

    function take(uint256 value) external {
        assetToken.transfer(msg.sender, value);
    }
}

contract SparkVaultAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockSparkVault internal vault;

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockSparkVault(asset);
        asset.mint(address(vault), 100 ether);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(SparkVaultAssertion).creationCode, abi.encode(address(vault), address(asset))
        );
        cl.assertion(address(vault), createData, SparkVaultAssertion.assertSparkTakeAccounting.selector);
    }

    function testTakeAccountingPassesWhenOutstandingTracksLiquidity() public {
        _arm();
        vault.take(10 ether);
    }

    function testTakeAccountingPassesWhenExcessLiquidityKeepsOutstandingAtZero() public {
        asset.mint(address(vault), 50 ether);
        _arm();
        vault.take(10 ether);
    }

    function testTakeAccountingTripsWhenOutstandingDoesNotIncrease() public {
        vault.setBreakOutstanding(true);

        _arm();
        vm.expectRevert(bytes("SparkVault: bad post-take assetsOutstanding"));
        vault.take(10 ether);
    }
}
