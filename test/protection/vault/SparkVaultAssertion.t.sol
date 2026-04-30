// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ERC4626Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol";

import {SparkVaultAssertion} from "../../../src/protection/vault/examples/SparkVaultAssertion.sol";
import {
    ISparkVaultLiquidityLike,
    ISparkVaultRateLike,
    ISparkVaultReferralLike
} from "../../../src/protection/vault/examples/SparkVaultInterfaces.sol";

contract SparkVaultAssertionTest is Test {
    function testSparkVaultAssertionDeploys() external {
        ERC20Mock asset = new ERC20Mock();
        ERC4626Mock vault = new ERC4626Mock(address(asset));
        SparkVaultAssertion assertion = new SparkVaultAssertion(address(vault), 50, 1_000, 24 hours);

        assertTrue(address(assertion) != address(0));
    }

    function testSparkReferralSelectorsMatchExpectedSignatures() external pure {
        assertEq(ISparkVaultReferralLike.deposit.selector, bytes4(keccak256("deposit(uint256,address,uint16)")));
        assertEq(ISparkVaultReferralLike.mint.selector, bytes4(keccak256("mint(uint256,address,uint16)")));
    }

    function testSparkRateAndLiquiditySelectorsMatchExpectedSignatures() external pure {
        assertEq(ISparkVaultRateLike.drip.selector, bytes4(keccak256("drip()")));
        assertEq(ISparkVaultRateLike.setVsr.selector, bytes4(keccak256("setVsr(uint256)")));
        assertEq(ISparkVaultLiquidityLike.take.selector, bytes4(keccak256("take(uint256)")));
        assertEq(ISparkVaultLiquidityLike.assetsOutstanding.selector, bytes4(keccak256("assetsOutstanding()")));
    }
}
