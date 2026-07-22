// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {BalancerV3VaultAssertion} from "../src/BalancerV3VaultAssertion.sol";
import {
    AddLiquidityKind,
    AddLiquidityParams,
    RemoveLiquidityKind,
    RemoveLiquidityParams,
    SwapKind,
    VaultSwapParams
} from "../src/BalancerV3VaultInterfaces.sol";
import {MockBalancerV3Pool, MockBalancerV3Vault, MockRateProvider, RateManipulatingRouter} from "./BalancerV3Mocks.sol";

contract BalancerV3VaultAssertionTest is Test, CredibleTest {
    uint256 internal constant INVARIANT_DUST_TOLERANCE = 0; // absolute invariant units
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
            abi.encode(
                address(vault), address(pool), vault.swapHooks(), INVARIANT_DUST_TOLERANCE, RATE_DRIFT_TOLERANCE_BPS
            )
        );
        cl.assertion(address(vault), createData, fnSelector);
    }

    function _swapParams(address targetPool) internal view returns (VaultSwapParams memory) {
        return VaultSwapParams({
            kind: SwapKind.EXACT_IN,
            pool: targetPool,
            tokenIn: address(token0),
            tokenOut: address(token1),
            amountGivenRaw: 10e18,
            limitRaw: 0,
            userData: ""
        });
    }

    function _swap(address targetPool) internal {
        vault.swap(_swapParams(targetPool));
    }

    function _addLiquidityParams(address targetPool) internal view returns (AddLiquidityParams memory params) {
        params.pool = targetPool;
        params.to = address(this);
        params.maxAmountsIn = new uint256[](2);
        params.minBptAmountOut = 0;
        params.kind = AddLiquidityKind.UNBALANCED;
        params.userData = "";
    }

    function _removeLiquidityParams(address targetPool) internal view returns (RemoveLiquidityParams memory params) {
        params.pool = targetPool;
        params.from = address(this);
        params.maxBptAmountIn = 1;
        params.minAmountsOut = new uint256[](2);
        params.kind = RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN;
        params.userData = "";
    }

    // --- assertSwapPreservesPoolInvariant ------------------------------------

    function testHonestSwapPassesInvariantAssertion() public {
        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        _swap(address(pool));
    }

    /// @notice The Vault deducts pending yield fees before adding swap input. Raw tokenIn balance
    ///         can therefore fall across an honest small swap; fee-adjusted live balance still
    ///         moves in the correct direction and is the relevant input to pool math.
    function testHonestSwapWithPendingYieldFeesPassesInvariantAssertion() public {
        vault.seedPendingYieldFee(address(token0), 20e18);

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
        vm.expectRevert(bytes("BalancerV3: swap increased tokenOut pool balance"));
        _swap(address(pool));
    }

    /// @notice Pools configured at assertion deployment with before/after-swap hooks are outside
    ///         the swap check's scope: those hooks may legitimately reenter the Vault mid-swap, so
    ///         call-boundary snapshots cannot attribute deltas to the core swap. A failure knob
    ///         that would otherwise trip must pass once the deployment marks the pool as hooked.
    function testHookedPoolSwapChecksAreSkipped() public {
        vault.setSwapHooks(true);
        vault.setMode(MockBalancerV3Vault.Mode.InvariantLoss);

        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        _swap(address(pool));
    }

    /// @notice Transient manipulation around the swap: rate doubled before the swap call and
    ///         restored after it, inside one transaction. Both transaction endpoints agree, but
    ///         the swap priced against the shifted rate — the per-operation baseline observation
    ///         catches what endpoint comparison cannot.
    function testTransientRateManipulationAroundSwapTrips() public {
        RateManipulatingRouter router = new RateManipulatingRouter(vault, rateProvider);
        token0.mint(address(router), 100e18);
        router.approveVault(address(token0));

        _arm(BalancerV3VaultAssertion.assertSwapPreservesPoolInvariant.selector);
        vm.expectRevert(bytes("BalancerV3: swap priced against rate beyond drift bound"));
        router.manipulateSwapRestore(_swapParams(address(pool)));
    }

    /// @notice Documents the endpoint-comparison gap the per-operation check exists for: the same
    ///         manipulate-swap-restore transaction passes the tx-end drift assertion because the
    ///         pre-tx and post-tx rates are equal.
    function testTransientRateManipulationPassesEndpointDrift() public {
        RateManipulatingRouter router = new RateManipulatingRouter(vault, rateProvider);
        token0.mint(address(router), 100e18);
        router.approveVault(address(token0));

        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        router.manipulateSwapRestore(_swapParams(address(pool)));
    }

    function testTransientRateManipulationAroundAddLiquidityTrips() public {
        RateManipulatingRouter router = new RateManipulatingRouter(vault, rateProvider);

        _arm(BalancerV3VaultAssertion.assertOperationRatesWithinBaseline.selector);
        vm.expectRevert(bytes("BalancerV3: liquidity priced against rate beyond drift bound"));
        router.manipulateAddLiquidityRestore(_addLiquidityParams(address(pool)));
    }

    function testHonestAddLiquidityPassesScopedRateAssertion() public {
        _arm(BalancerV3VaultAssertion.assertOperationRatesWithinBaseline.selector);
        vault.addLiquidity(_addLiquidityParams(address(pool)));
    }

    function testTransientRateManipulationAroundRemoveLiquidityTrips() public {
        RateManipulatingRouter router = new RateManipulatingRouter(vault, rateProvider);

        _arm(BalancerV3VaultAssertion.assertOperationRatesWithinBaseline.selector);
        vm.expectRevert(bytes("BalancerV3: liquidity priced against rate beyond drift bound"));
        router.manipulateRemoveLiquidityRestore(_removeLiquidityParams(address(pool)));
    }

    // --- assertPoolAccountingWithinVaultCustody -------------------------------

    function testHonestSwapPassesCustodyAssertion() public {
        _arm(BalancerV3VaultAssertion.assertPoolAccountingWithinVaultCustody.selector);
        _swap(address(pool));
    }

    function testReserveSkimTripsCustody() public {
        vault.setMode(MockBalancerV3Vault.Mode.ReserveSkim);

        _arm(BalancerV3VaultAssertion.assertPoolAccountingWithinVaultCustody.selector);
        vm.expectRevert(bytes("BalancerV3: vault reserves exceed real token custody"));
        _swap(address(pool));
    }

    function testPhantomPoolBalanceTripsCustody() public {
        vault.setMode(MockBalancerV3Vault.Mode.PhantomBalance);

        _arm(BalancerV3VaultAssertion.assertPoolAccountingWithinVaultCustody.selector);
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

    /// @notice A provider already registered for the pool pre-tx that answered ZERO pre-tx is a
    ///         broken baseline, not a deployment lifecycle: it must fail instead of granting the
    ///         registration exemption and legitimizing an arbitrary post-tx rate.
    function testZeroBaselineForRegisteredProviderTrips() public {
        rateProvider.setRate(0);
        vault.setMode(MockBalancerV3Vault.Mode.RateShift); // 0 -> 1e18 during the swap

        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        vm.expectRevert(bytes("BalancerV3: zero rate baseline"));
        _swap(address(pool));
    }

    /// @notice A provider deployed and registered within the transaction has no pre-tx baseline by
    ///         construction: the deployment lifecycle is exempt from the drift comparison (only the
    ///         nonzero post-state is enforced) instead of reverting on the missing baseline read.
    function testProviderRegisteredDuringTxIsExempt() public {
        vault.registerNewRateProvider();

        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        vault.initialize(address(pool), address(this), new address[](0), new uint256[](0), 0, "");
    }

    function testProviderRegisteredDuringTxPassesScopedInitializationRateCheck() public {
        vault.registerNewRateProvider();

        _arm(BalancerV3VaultAssertion.assertOperationRatesWithinBaseline.selector);
        vault.initialize(address(pool), address(this), new address[](0), new uint256[](0), 0, "");
    }

    /// @notice Recovery mode disables the rate assertion entirely: Balancer's recovery exit uses
    ///         raw balances precisely because providers may be broken, and a broken or moved
    ///         provider must never block that path.
    function testRecoveryModeSkipsRateAssertion() public {
        vault.setRecoveryMode(true);
        vault.setMode(MockBalancerV3Vault.Mode.RateShift);

        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        _swap(address(pool));
    }

    /// @notice A transaction that moves the rate without touching the watched pool's accounting is
    ///         out of the drift assertion's scope, so the watched provider never becomes a
    ///         dependency of unrelated Vault traffic. The residual is documented on the assertion:
    ///         a later transaction consuming the moved rate touches the pool and is examined.
    function testRateOnlyTransactionIsOutOfScope() public {
        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        vault.shiftRateOnly();
    }

    /// @notice The tx-end gates are pure Vault storage comparisons on the watched pool, so
    ///         unrelated singleton traffic is skipped without consulting the rate provider even
    ///         when that provider is broken: the watched pool never becomes a liveness dependency
    ///         of the rest of the singleton.
    function testUnrelatedVaultTrafficIgnoresBrokenProvider() public {
        rateProvider.setRate(0); // would trip "returned zero rate" if the drift loop ran

        _arm(BalancerV3VaultAssertion.assertTokenRatesWithinDriftBound.selector);
        vault.unrelatedVaultCall();
    }

    /// @notice A custody imbalance that predates the transaction is flagged at the transaction
    ///         that caused it, not re-litigated by every later unrelated transaction: the gate
    ///         sees no watched-pool accounting delta and skips the per-token custody reads.
    function testUnrelatedVaultTrafficSkipsPreexistingCustodyImbalance() public {
        vault.seedPoolBalance(0, 2_000e18); // pool claims exceed reserves before the armed tx

        _arm(BalancerV3VaultAssertion.assertPoolAccountingWithinVaultCustody.selector);
        vault.unrelatedVaultCall();
    }

    // --- wiring ----------------------------------------------------------------

    function testDeploys() public {
        BalancerV3VaultAssertion assertion = new BalancerV3VaultAssertion(
            address(vault), address(pool), false, INVARIANT_DUST_TOLERANCE, RATE_DRIFT_TOLERANCE_BPS
        );
        assertTrue(address(assertion) != address(0));
    }

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("BalancerV3: zero vault"));
        new BalancerV3VaultAssertion(address(0), address(pool), false, 0, RATE_DRIFT_TOLERANCE_BPS);
    }

    function testRejectsZeroPool() public {
        vm.expectRevert(bytes("BalancerV3: zero pool"));
        new BalancerV3VaultAssertion(address(vault), address(0), false, 0, RATE_DRIFT_TOLERANCE_BPS);
    }
}
