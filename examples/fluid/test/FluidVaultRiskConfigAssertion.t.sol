// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {FluidVaultRiskConfigAssertion} from "../src/FluidVaultRiskConfigAssertion.sol";

/// @notice Mock FluidVaultResolver returning a single packed `vaultVariables2` word.
contract MockVaultResolver {
    uint256 internal packed;

    function set(uint256 vaultVariables2_) external {
        packed = vaultVariables2_;
    }

    function getVaultVariables2Raw(address) external view returns (uint256) {
        return packed;
    }
}

/// @notice Mock vault adopter; any call fires the tx-end config check.
contract MockVault {
    function poke() external {}
}

contract FluidVaultRiskConfigAssertionTest is Test, CredibleTest {
    MockVaultResolver internal resolver;
    MockVault internal vault;

    function setUp() public {
        resolver = new MockVaultResolver();
        vault = new MockVault();
        // Healthy ordering: CF 75% (750), LT 85% (850), LML 90% (900) stored as input/10;
        // penalty 5% (500) stored in 1e2. 9000 + 500 = 9500 <= 9970.
        resolver.set(_pack(750, 850, 900, 500));
    }

    function _pack(uint256 cf, uint256 lt, uint256 lml, uint256 penalty) internal pure returns (uint256) {
        return (cf << 32) | (lt << 42) | (lml << 52) | (penalty << 72);
    }

    function _arm() internal {
        bytes memory createData =
            abi.encodePacked(type(FluidVaultRiskConfigAssertion).creationCode, abi.encode(address(resolver)));
        cl.assertion(address(vault), createData, FluidVaultRiskConfigAssertion.assertRiskConfigOrdering.selector);
    }

    function testHealthyConfigPasses() public {
        _arm();
        vault.poke();
    }

    function testInvertedOrderingTrips() public {
        // CF (900) >= LT (850): positions could open at/above the liquidation line.
        resolver.set(_pack(900, 850, 950, 500));
        _arm();
        vm.expectRevert(bytes("Fluid: collateral factor >= liquidation threshold"));
        vault.poke();
    }

    function testPenaltyOverConsumesCollateralTrips() public {
        // LML 95% (950 -> 9500 in 1e2) + penalty 5% (500) = 10000 > 9970.
        resolver.set(_pack(750, 850, 950, 500));
        _arm();
        vm.expectRevert(bytes("Fluid: liquidation max limit + penalty above 99.7%"));
        vault.poke();
    }
}
