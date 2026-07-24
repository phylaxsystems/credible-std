// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {MellowSubvaultAllocationAssertion} from "../src/MellowSubvaultAllocationAssertion.sol";
import {MockERC20, MockMellowSubvault} from "./MellowMocks.sol";

contract MellowSubvaultAllocationAssertionTest is Test, CredibleTest {
    MockMellowSubvault internal subvault;
    MockERC20 internal asset; // underlying supplied into the market
    MockERC20 internal aToken; // supply receipt (subvault's supplied position + reserve custody)

    function setUp() public {
        subvault = new MockMellowSubvault();
        asset = new MockERC20();
        aToken = new MockERC20();

        // Pre-state: subvault has 100 supplied; the reserve holds 1000 withdrawable.
        aToken.setBalance(address(subvault), 100e18);
        asset.setBalance(address(aToken), 1_000e18);
    }

    function _arm(uint256 minExitLiquidityBps) internal {
        bytes memory createData = abi.encodePacked(
            type(MellowSubvaultAllocationAssertion).creationCode,
            abi.encode(address(subvault), address(asset), address(aToken), minExitLiquidityBps)
        );
        cl.assertion(address(subvault), createData, MellowSubvaultAllocationAssertion.assertHealthyAllocation.selector);
    }

    // --- Honest paths ------------------------------------------------------

    function testAllocationIntoLiquidMarketPasses() public {
        // Grow the position to 150; reserve still holds 200 (>= 150 = full position withdrawable).
        _arm(10_000);
        subvault.allocate(address(aToken), address(asset), 150e18, 200e18);
    }

    function testNoAllocationSkipsCheck() public {
        // Even with the reserve drained to 10 (< 100 supplied), a tx that does not grow the
        // position is not an allocation, so the liquidity floor is not enforced.
        asset.setBalance(address(aToken), 10e18);
        _arm(10_000);
        subvault.noop();
    }

    function testReducingPositionPasses() public {
        // Withdrawing from an illiquid market (reserve only 10) is always allowed.
        _arm(10_000);
        subvault.allocate(address(aToken), address(asset), 50e18, 10e18);
    }

    // --- Malicious path ----------------------------------------------------

    function testAllocationIntoIlliquidMarketTrips() public {
        // Grow the position to 150 but the reserve has been borrowed down to 100 (< 150).
        _arm(10_000);
        vm.expectRevert(bytes("MellowSubvault: allocation into illiquid market"));
        subvault.allocate(address(aToken), address(asset), 150e18, 100e18);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroSubvault() public {
        vm.expectRevert(bytes("MellowSubvault: zero subvault"));
        new MellowSubvaultAllocationAssertion(address(0), address(asset), address(aToken), 10_000);
    }

    function testRejectsZeroAsset() public {
        vm.expectRevert(bytes("MellowSubvault: zero asset"));
        new MellowSubvaultAllocationAssertion(address(subvault), address(0), address(aToken), 10_000);
    }

    function testRejectsZeroAToken() public {
        vm.expectRevert(bytes("MellowSubvault: zero aToken"));
        new MellowSubvaultAllocationAssertion(address(subvault), address(asset), address(0), 10_000);
    }

    function testRejectsZeroExitLiquidityBps() public {
        vm.expectRevert(bytes("MellowSubvault: invalid exit bps"));
        new MellowSubvaultAllocationAssertion(address(subvault), address(asset), address(aToken), 0);
    }

    function testDeploys() public {
        MellowSubvaultAllocationAssertion assertion =
            new MellowSubvaultAllocationAssertion(address(subvault), address(asset), address(aToken), 10_000);
        assertTrue(address(assertion) != address(0));
    }
}
