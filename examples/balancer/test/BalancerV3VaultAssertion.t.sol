// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {BalancerV3VaultAssertion} from "../src/BalancerV3VaultAssertion.sol";
import {SwapKind, VaultSwapParams} from "../src/BalancerV3VaultInterfaces.sol";
import {MockBalancerV3Pool, MockBalancerV3Vault, MockRateProvider} from "./BalancerV3Mocks.sol";

contract BalancerV3VaultAssertionTest is Test, CredibleTest {
    uint256 internal constant INVARIANT_DUST_TOLERANCE_BPS = 0;
    uint256 internal constant RATE_DRIFT_TOLERANCE_BPS = 100; // 1%

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    MockRateProvider internal rateProvider;
    MockBalancerV3Pool internal pool;
    MockBalancerV3Vault internal vault;

    function setUp() public {
        token0 = new ERC20Mock();
        token1 = new ERC20Mock();
        rateProvider = new MockRateProvider();
        pool = new MockBalancerV3Pool();
        vault = new MockBalancerV3Vault(address(pool), address(token0), address(token1), rateProvider);

        // Custody exactly backs reserves; reserves exceed pool balances + fees with headroom.
        token0.mint(address(vault), 1_000e18);
        token1.mint(address(vault), 1_000e18);
        vault.seedReserves(address(token0), 1_000e18);
        vault.seedReserves(address(token1), 1_000e18);
        vault.seedPoolBalance(0, 500e18);
        vault.seedPoolBalance(1, 500e18);

        token0.mint(address(this), 100e18);
        token0.approve(address(vault), type(uint256).max);
        vault.setSkimReceiver(makeAddr("skimReceiver"));
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(BalancerV3VaultAssertion).creationCode,
            abi.encode(address(vault), address(pool), INVARIANT_DUST_TOLERANCE_BPS, RATE_DRIFT_TOLERANCE_BPS)
        );
        cl.assertion(address(vault), createData, fnSelector);
    }

    function _swap(address targetPool) internal {
        vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: targetPool,
                tokenIn: address(token0),
                tokenOut: address(token1),
                amountGivenRaw: 10e18,
                limitRaw: 0,
                userData: ""
            })
        );
    }

    // --- assertSwapPreservesPoolInvariant ------------------------------------

    function testHonestSwapPassesInvariantAssertion() public {
        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        _swap(address(pool));
    }

    function testSwapOnUnwatchedPoolIsIgnored() public {
        vault.setMode(MockBalancerV3Vault.Mode.InvariantLoss);

        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        _swap(makeAddr("otherPool"));
    }

    function testInvariantLossTrips() public {
        vault.setMode(MockBalancerV3Vault.Mode.InvariantLoss);

        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        vm.expectRevert(bytes("BalancerV3: swap decreased pool invariant"));
        _swap(address(pool));
    }

    function testSupplyDriftTrips() public {
        vault.setMode(MockBalancerV3Vault.Mode.SupplyDrift);

        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        vm.expectRevert(bytes("BalancerV3: swap changed BPT supply"));
        _swap(address(pool));
    }

    function testBalancesAgainstSwapDirectionTrip() public {
        vault.setMode(MockBalancerV3Vault.Mode.BalanceSwapEnds);

        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        vm.expectRevert(bytes("BalancerV3: swap decreased tokenIn pool balance"));
        _swap(address(pool));
    }

    // --- assertVaultCustodyCoversPoolAccounting -------------------------------

    function testHonestSwapPassesCustodyAssertion() public {
        _arm(BalancerV3VaultAssertion.assertVaultCustodyCoversPoolAccounting.selector);
        _swap(address(pool));
    }

    function testReserveSkimTripsCustody() public {
        vault.setMode(MockBalancerV3Vault.Mode.ReserveSkim);

        _arm(BalancerV3VaultAssertion.assertVaultCustodyCoversPoolAccounting.selector);
        vm.expectRevert(bytes("BalancerV3: vault reserves exceed real token custody"));
        _swap(address(pool));
    }

    function testPhantomPoolBalanceTripsCustody() public {
        vault.setMode(MockBalancerV3Vault.Mode.PhantomBalance);

        _arm(BalancerV3VaultAssertion.assertVaultCustodyCoversPoolAccounting.selector);
        vm.expectRevert(bytes("BalancerV3: pool accounting exceeds vault reserves"));
        _swap(address(pool));
    }

    // --- assertTokenRatesWithinDriftBound --------------------------------------

    function testHonestSwapPassesRateAssertion() public {
        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        _swap(address(pool));
    }

    function testRateShiftTrips() public {
        vault.setMode(MockBalancerV3Vault.Mode.RateShift);

        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        vm.expectRevert(bytes("BalancerV3: token rate moved beyond drift bound"));
        _swap(address(pool));
    }

    // --- wiring ----------------------------------------------------------------

    function testDeploys() public {
        BalancerV3VaultAssertion assertion = new BalancerV3VaultAssertion(
            address(vault), address(pool), INVARIANT_DUST_TOLERANCE_BPS, RATE_DRIFT_TOLERANCE_BPS
        );
        assertTrue(address(assertion) != address(0));
    }

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("BalancerV3: zero vault"));
        new BalancerV3VaultAssertion(address(0), address(pool), 0, RATE_DRIFT_TOLERANCE_BPS);
    }

    function testRejectsZeroPool() public {
        vm.expectRevert(bytes("BalancerV3: zero pool"));
        new BalancerV3VaultAssertion(address(vault), address(0), 0, RATE_DRIFT_TOLERANCE_BPS);
    }
}
