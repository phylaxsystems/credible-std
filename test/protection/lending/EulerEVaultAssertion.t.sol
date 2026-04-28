// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {
    EulerEVaultAssertion,
    EulerLayeredOutflowCircuitBreakerAssertion,
    EulerLiquidationQuoteAssertion,
    EulerPerCallSharePriceAssertion,
    EulerSmartInflowCircuitBreakerAssertion,
    EulerSmartOutflowCircuitBreakerAssertion,
    EulerUserStorageAccountingAssertion
} from "../../../src/protection/lending/examples/EulerEVaultAssertion.sol";
import {IEulerEVaultLike} from "../../../src/protection/lending/examples/EulerEVaultInterfaces.sol";
import {
    EulerERC4626CallSandwichAssertion
} from "../../../src/protection/lending/examples/EulerEVaultSandwichAssertion.sol";

contract EulerEVaultAssertionTest is Test {
    function testEulerEVaultAssertionsDeploy() external {
        address asset = address(0xA11CE);

        EulerEVaultAssertion bundled = new EulerEVaultAssertion(asset, 50, 2_000, 24 hours, 1_000, 24 hours);
        EulerUserStorageAccountingAssertion storageAccounting = new EulerUserStorageAccountingAssertion();
        EulerPerCallSharePriceAssertion sharePrice = new EulerPerCallSharePriceAssertion(50);
        EulerLiquidationQuoteAssertion liquidationQuote = new EulerLiquidationQuoteAssertion();
        EulerSmartInflowCircuitBreakerAssertion inflow =
            new EulerSmartInflowCircuitBreakerAssertion(asset, 2_000, 24 hours);
        EulerSmartOutflowCircuitBreakerAssertion outflow =
            new EulerSmartOutflowCircuitBreakerAssertion(asset, 1_000, 24 hours);
        EulerLayeredOutflowCircuitBreakerAssertion layeredOutflow =
            new EulerLayeredOutflowCircuitBreakerAssertion(asset);
        EulerERC4626CallSandwichAssertion sandwich = new EulerERC4626CallSandwichAssertion();

        assertTrue(address(bundled) != address(0));
        assertTrue(address(storageAccounting) != address(0));
        assertTrue(address(sharePrice) != address(0));
        assertTrue(address(liquidationQuote) != address(0));
        assertTrue(address(inflow) != address(0));
        assertTrue(address(outflow) != address(0));
        assertTrue(address(layeredOutflow) != address(0));
        assertTrue(address(sandwich) != address(0));
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
