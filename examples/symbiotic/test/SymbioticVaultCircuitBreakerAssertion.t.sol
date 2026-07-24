// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SymbioticVaultCircuitBreakerAssertion, SymbioticVaultCircuitBreakerProtection} from
    "../src/SymbioticVaultCircuitBreakerAssertion.sol";

contract MockSymbioticVault {
    ERC20Mock public immutable asset;

    constructor(ERC20Mock asset_) {
        asset = asset_;
    }

    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares) {
        asset.transfer(claimer, amount);
        return (amount, amount);
    }
}

contract SymbioticVaultCircuitBreakerAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockSymbioticVault internal vault;
    address internal alice = makeAddr("alice");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockSymbioticVault(asset);
        asset.mint(address(vault), 100 ether);
    }

    function _arm(bytes4 fnSelector) internal {
        SymbioticVaultCircuitBreakerAssertion.LiquidationRoute[] memory routes =
            new SymbioticVaultCircuitBreakerAssertion.LiquidationRoute[](1);
        routes[0] =
            SymbioticVaultCircuitBreakerAssertion.LiquidationRoute({target: makeAddr("liquidator"), selector: 0x12345678});

        bytes memory createData = abi.encodePacked(
            type(SymbioticVaultCircuitBreakerProtection).creationCode, abi.encode(address(vault), address(asset), routes)
        );
        cl.assertion(address(vault), createData, fnSelector);
    }

    function retiredNonCausalCircuitBreakerLargeOutflowTripsDailyHardStop() public {
        _arm(bytes4(keccak256("assertDailyHardStopCircuitBreaker()")));

        vm.expectRevert(bytes("SymbioticCircuitBreaker: daily hard outflow breaker tripped"));
        vault.withdraw(alice, 31 ether);
    }
}
