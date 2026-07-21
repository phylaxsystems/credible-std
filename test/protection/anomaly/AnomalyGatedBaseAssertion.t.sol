// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";
import {AnomalyCompositeAssertion} from "credible-std/protection/anomaly/AnomalyCompositeAssertion.sol";
import {CompositeTxEndHarness} from "./AnomalyCompositeAssertion.t.sol";
import {MockERC20, Vault} from "./AnomalyTestMocks.sol";

// Base-primitive coverage for the drain ratio in `_drains`: exact threshold boundaries, the
// 512-bit `mulDivDown` overflow regression, codeless-token fail-open, and two fuzz properties.
// The verdict oracle: while anomalous, block iff `net * 10_000 / preBalance >= fracBps`; while
// not anomalous, never block. The gate is overridden to a constructor bool as in the other
// anomaly suites.

contract TestAnomalyDrainRatio is CredibleTest, Test {
    uint16 internal constant THRESHOLD_BPS = 205;
    uint256 internal constant DRAIN_FRAC_BPS = 250; // 2.5% of the reserve
    uint256 internal constant SUPPLY = 100 ether;
    address internal constant SINK = address(0x5117);

    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        token.mint(address(vault), SUPPLY);
    }

    function _config(address token_, uint256 fracBps)
        internal
        view
        returns (AnomalyCompositeAssertion.Config memory c)
    {
        c.target = address(vault);
        c.anomalyThresholdBps = THRESHOLD_BPS;
        c.useDrain = true;
        c.outflowTarget = address(vault);
        c.outflowToken = token_;
        c.outflowFracBps = fracBps;
    }

    function _register(uint256 fracBps, bool anomalous) internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(CompositeTxEndHarness).creationCode, abi.encode(_config(address(token), fracBps), anomalous)
            ),
            fnSelector: AnomalyCompositeAssertion.assertComposite.selector
        });
    }

    // --- threshold boundaries ---

    /// A drain of exactly the fraction corroborates: the comparison is `>=`.
    function test_drain_at_exact_fraction_blocks() public {
        _register(DRAIN_FRAC_BPS, true);
        vm.expectRevert();
        vault.drain(SINK, SUPPLY * DRAIN_FRAC_BPS / 10_000);
    }

    /// One wei below the fraction stays in the alert cell.
    function test_drain_one_wei_below_fraction_passes() public {
        _register(DRAIN_FRAC_BPS, true);
        vault.drain(SINK, SUPPLY * DRAIN_FRAC_BPS / 10_000 - 1);
    }

    /// At the 10_000 cap only a full drain corroborates.
    function test_full_drain_blocks_at_cap_fraction() public {
        _register(10_000, true);
        vm.expectRevert();
        vault.drain(SINK, SUPPLY);
    }

    /// At the cap fraction, one wei short of a full drain rounds down to 9_999 bps and passes.
    function test_near_full_drain_passes_at_cap_fraction() public {
        _register(10_000, true);
        vault.drain(SINK, SUPPLY - 1);
    }

    // --- overflow regression (512-bit ratio) ---

    /// Regression: with a 2^250 pre-balance, `net * 10_000` overflows uint256 for a 2^244 drain,
    /// so the plain-math ratio panicked here and blocked a below-threshold (1.5625%) drain
    /// without corroboration. The `mulDivDown` ratio reads 156 bps and passes.
    function test_huge_balance_below_threshold_does_not_block() public {
        token.mint(address(vault), (1 << 250) - SUPPLY);
        _register(DRAIN_FRAC_BPS, true);
        vault.drain(SINK, 1 << 244);
    }

    /// The same huge balance still blocks above threshold: 2^245 of 2^250 is 312 bps.
    function test_huge_balance_above_threshold_blocks() public {
        token.mint(address(vault), (1 << 250) - SUPPLY);
        _register(DRAIN_FRAC_BPS, true);
        vm.expectRevert();
        vault.drain(SINK, 1 << 245);
    }

    // --- fail-open reads ---

    /// A codeless (but nonzero) token fails open: every balance read reports zero, nothing
    /// corroborates, and the anomalous transaction stays in the alert cell.
    function test_codeless_token_fails_open() public {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(CompositeTxEndHarness).creationCode,
                abi.encode(_config(makeAddr("codeless"), DRAIN_FRAC_BPS), true)
            ),
            fnSelector: AnomalyCompositeAssertion.assertComposite.selector
        });
        vault.poke();
    }

    // --- fuzz properties ---

    /// Oracle property: while anomalous, the composite blocks iff the drain ratio reaches the
    /// fraction. The reference computes the same predicate with plain math, exact on this domain.
    function testFuzz_blocks_iff_ratio_reaches_fraction(uint256 amount, uint256 fracBps) public {
        fracBps = bound(fracBps, 1, 10_000);
        amount = bound(amount, 0, SUPPLY);
        _register(fracBps, true);
        if (amount * 10_000 / SUPPLY >= fracBps) {
            vm.expectRevert();
        }
        vault.drain(SINK, amount);
    }

    /// Gate invariant: while not anomalous, no drain blocks, whatever its size or the fraction.
    function testFuzz_never_blocks_when_not_anomalous(uint256 amount, uint256 fracBps) public {
        fracBps = bound(fracBps, 1, 10_000);
        amount = bound(amount, 0, SUPPLY);
        _register(fracBps, false);
        vault.drain(SINK, amount);
    }
}
