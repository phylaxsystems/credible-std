// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {
    EulerEVaultAssertion,
    EulerLiquidationQuoteAssertion,
    EulerPerCallSharePriceAssertion,
    EulerSmartOutflowCircuitBreakerAssertion,
    EulerUserStorageAccountingAssertion
} from "../../../src/protection/lending/examples/EulerEVaultAssertion.sol";
import {IEulerEVaultLike} from "../../../src/protection/lending/examples/EulerEVaultInterfaces.sol";

contract EulerEVaultAssertionTest is Test {
    function testEulerEVaultAssertionsDeploy() external {
        address asset = address(0xA11CE);

        EulerEVaultAssertion bundled = new EulerEVaultAssertion(asset, 50, 1_000, 24 hours);
        EulerUserStorageAccountingAssertion storageAccounting = new EulerUserStorageAccountingAssertion();
        EulerPerCallSharePriceAssertion sharePrice = new EulerPerCallSharePriceAssertion(50);
        EulerLiquidationQuoteAssertion liquidationQuote = new EulerLiquidationQuoteAssertion();
        EulerSmartOutflowCircuitBreakerAssertion outflow =
            new EulerSmartOutflowCircuitBreakerAssertion(asset, 1_000, 24 hours);

        assertTrue(address(bundled) != address(0));
        assertTrue(address(storageAccounting) != address(0));
        assertTrue(address(sharePrice) != address(0));
        assertTrue(address(liquidationQuote) != address(0));
        assertTrue(address(outflow) != address(0));
    }

    function testEulerEVaultSelectorsMatchExpectedSignatures() external pure {
        assertEq(IEulerEVaultLike.deposit.selector, bytes4(keccak256("deposit(uint256,address)")));
        assertEq(IEulerEVaultLike.withdraw.selector, bytes4(keccak256("withdraw(uint256,address,address)")));
        assertEq(IEulerEVaultLike.borrow.selector, bytes4(keccak256("borrow(uint256,address)")));
        assertEq(IEulerEVaultLike.repayWithShares.selector, bytes4(keccak256("repayWithShares(uint256,address)")));
        assertEq(IEulerEVaultLike.pullDebt.selector, bytes4(keccak256("pullDebt(uint256,address)")));
        assertEq(IEulerEVaultLike.liquidate.selector, bytes4(keccak256("liquidate(address,address,uint256,uint256)")));
        assertEq(
            IEulerEVaultLike.checkLiquidation.selector, bytes4(keccak256("checkLiquidation(address,address,address)"))
        );
    }
}
