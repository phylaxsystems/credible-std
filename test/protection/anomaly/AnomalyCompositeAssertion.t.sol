// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";
import {Sensitivity} from "credible-std/Sensitivity.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {AnomalyCompositeAssertion} from "credible-std/protection/anomaly/AnomalyCompositeAssertion.sol";
import {AnomalyGatedBaseAssertion} from "credible-std/protection/anomaly/AnomalyGatedBaseAssertion.sol";
import {MockERC20, MockOracle, MockVault4626, Vault} from "./AnomalyTestMocks.sol";

// `assertComposite` runs only once the anomaly trigger has fired, so these tests cover the
// corroboration, operator, and exclusive-set logic that follows it.
//
// Released pcl has no anomaly precompile, so they fire from a tx-end trigger standing in for the
// anomaly trigger. Whether that trigger fires at a given sensitivity level is the executor's
// decision, tested in its own selection suite.

/// @notice The composite fired by a tx-end trigger standing in for the anomaly trigger, so the
/// corroboration logic runs without the anomaly precompile.
contract CompositeTxEndHarness is AnomalyCompositeAssertion {
    constructor(Config memory c) AnomalyCompositeAssertion(c) {}

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertComposite.selector);
    }
}

/// @notice The composite with a protocol-specific `_extra` leg. The leg corroborates when the
/// protocol reports itself unhealthy (`flag == false`) post-tx.
contract CompositeWithHealthTxEnd is AnomalyCompositeAssertion {
    address internal immutable healthTarget;

    constructor(Config memory c, address healthTarget_) AnomalyCompositeAssertion(c) {
        healthTarget = healthTarget_;
    }

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertComposite.selector);
    }

    function _extra() internal override returns (bool enabled, bool corroborates) {
        PhEvm.StaticCallResult memory result =
            ph.staticcallAt(healthTarget, abi.encodeWithSignature("flag()"), 50_000, _postTx());
        bool healthy = result.ok && abi.decode(result.data, (bool));
        return (true, !healthy);
    }
}

/// @notice Proves the composite disposition once the trigger has fired: `block = H`, and the
/// exclusive-set fall-through when `H` is silent, under both the OR and the AND operator. The AND
/// is the case a fleet of single-heuristic assertions cannot express.
contract TestAnomalyCompositeAssertion is CredibleTest, Test {
    uint8 internal constant LEVEL = Sensitivity.RECOMMENDED;
    uint256 internal constant DRAIN_FRAC_BPS = 250; // 2.5% of the reserve
    uint256 internal constant SUPPLY = 100 ether;
    address internal constant SINK = address(0x5117);
    address internal constant IMPL = address(0x1);

    MockERC20 internal token;
    Vault internal vault;
    Vault internal remote;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        remote = new Vault(token);
        token.mint(address(vault), SUPPLY);
    }

    /// A config with every heuristic off; each test turns on what it needs.
    function _base() internal view returns (AnomalyCompositeAssertion.Config memory c) {
        c.target = address(vault);
        c.sensitivity = LEVEL;
    }

    function _withDrain(AnomalyCompositeAssertion.Config memory c)
        internal
        view
        returns (AnomalyCompositeAssertion.Config memory)
    {
        c.useDrain = true;
        c.outflowTarget = address(vault);
        c.outflowToken = address(token);
        c.outflowFracBps = DRAIN_FRAC_BPS;
        return c;
    }

    function _withUpgrade(AnomalyCompositeAssertion.Config memory c)
        internal
        pure
        returns (AnomalyCompositeAssertion.Config memory)
    {
        c.useUpgrade = true; // ownerSlot stays 0: watch the EIP-1967 slots only
        return c;
    }

    function _register(AnomalyCompositeAssertion.Config memory c) internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(type(CompositeTxEndHarness).creationCode, abi.encode(c)),
            fnSelector: AnomalyCompositeAssertion.assertComposite.selector
        });
    }

    // --- OR operator: any one enabled heuristic blocks ---

    /// Anomalous and the tx drains: OR blocks.
    function test_or_drain_blocks() public {
        _register(_withUpgrade(_withDrain(_base())));
        vm.expectRevert();
        vault.drain(SINK, 90 ether);
    }

    /// Anomalous and the tx upgrades: OR blocks on the other leg.
    function test_or_upgrade_blocks() public {
        _register(_withUpgrade(_withDrain(_base())));
        vm.expectRevert();
        vault.upgradeTo(IMPL);
    }

    /// Anomalous but neither heuristic corroborates: the exclusive set. No revert (alert cell).
    function test_or_neither_is_exclusive_set_and_passes() public {
        _register(_withUpgrade(_withDrain(_base())));
        vault.poke();
    }

    // --- AND operator: every enabled heuristic must corroborate ---

    /// Anomalous, the tx drains AND upgrades in one tx: AND blocks.
    function test_and_both_blocks() public {
        AnomalyCompositeAssertion.Config memory c = _withUpgrade(_withDrain(_base()));
        c.requireAll = true;
        _register(c);
        vm.expectRevert();
        vault.drainAndUpgrade(SINK, 90 ether, IMPL);
    }

    /// Anomalous and the tx drains but does not upgrade: AND does not block (upgrade leg silent).
    function test_and_drain_only_passes() public {
        AnomalyCompositeAssertion.Config memory c = _withUpgrade(_withDrain(_base()));
        c.requireAll = true;
        _register(c);
        vault.drain(SINK, 90 ether);
    }

    /// Anomalous and the tx upgrades but does not drain: AND does not block (drain leg silent).
    function test_and_upgrade_only_passes() public {
        AnomalyCompositeAssertion.Config memory c = _withUpgrade(_withDrain(_base()));
        c.requireAll = true;
        _register(c);
        vault.upgradeTo(IMPL);
    }

    // --- the named upgrade target ---

    /// The upgrade leg watches the named `upgradeTarget`, not the focal: upgrading the remote blocks.
    function test_upgrade_target_watches_named_contract() public {
        AnomalyCompositeAssertion.Config memory c = _withUpgrade(_base());
        c.upgradeTarget = address(remote);
        _register(c);
        vm.expectRevert();
        vault.upgradeRemote(remote, IMPL);
    }

    /// With a named `upgradeTarget`, an upgrade of the focal itself is not watched: the exclusive
    /// set, no revert.
    function test_upgrade_target_ignores_focal_upgrade() public {
        AnomalyCompositeAssertion.Config memory c = _withUpgrade(_base());
        c.upgradeTarget = address(remote);
        _register(c);
        vault.upgradeTo(IMPL);
    }

    // --- the gate and the baseline ---

    /// A config with no heuristic enabled and no baseline opt-in reverts at deploy: blocking on the
    /// score alone must be explicit, not a default-initialized `Config`.
    function test_config_with_no_heuristic_reverts_at_deploy() public {
        vm.expectRevert(AnomalyCompositeAssertion.NoHeuristicEnabled.selector);
        new CompositeTxEndHarness(_base());
    }

    /// An enabled leg missing a parameter it reads reverts at deploy rather than shipping a
    /// silently inert or falsely blocking heuristic: the drain leg without its custody address,
    /// token, or a nonzero fraction; the accounting leg without its vault; the oracle leg without
    /// its feed or a selector-sized query.
    function test_misconfigured_legs_revert_at_deploy() public {
        AnomalyCompositeAssertion.Config memory c = _withDrain(_base());
        c.outflowTarget = address(0);
        _expectMisconfigured(c);

        c = _withDrain(_base());
        c.outflowToken = address(0);
        _expectMisconfigured(c);

        c = _withDrain(_base());
        c.outflowFracBps = 0;
        _expectMisconfigured(c);

        c = _withDrain(_base());
        c.outflowFracBps = 10_001;
        _expectMisconfigured(c);

        c = _base();
        c.useAccounting = true; // accountingVault stays 0
        c.shareToleranceBps = 200;
        _expectMisconfigured(c);

        c = _base();
        c.useOracle = true; // oracle stays 0
        c.oracleQuery = abi.encodeWithSignature("latestAnswer()");
        _expectMisconfigured(c);

        c = _base();
        c.useOracle = true;
        c.oracle = address(0x0123); // oracleQuery stays empty
        _expectMisconfigured(c);
    }

    function _expectMisconfigured(AnomalyCompositeAssertion.Config memory c) internal {
        vm.expectRevert(AnomalyGatedBaseAssertion.HeuristicMisconfigured.selector);
        new CompositeTxEndHarness(c);
    }

    /// A zero target reverts at deploy: `anomalyContext` can never score it, so the gate would
    /// never open and the assertion would be permanently inert.
    function test_zero_target_reverts_at_deploy() public {
        AnomalyCompositeAssertion.Config memory c = _withDrain(_base());
        c.target = address(0);
        vm.expectRevert(AnomalyGatedBaseAssertion.ZeroTarget.selector);
        new CompositeTxEndHarness(c);
    }

    /// The sensitivity must name a rung of the ladder, [1, 10], boundaries included. Level 0 is
    /// the "cleared nothing" sentinel an unscored target reads back, so accepting it would gate
    /// true on contracts the model never scored; above 10 names no level and could never fire.
    function test_sensitivity_range_boundaries_at_deploy() public {
        AnomalyCompositeAssertion.Config memory c = _withDrain(_base());
        c.sensitivity = 0;
        vm.expectRevert(AnomalyGatedBaseAssertion.SensitivityOutOfRange.selector);
        new CompositeTxEndHarness(c);

        c = _withDrain(_base());
        c.sensitivity = 11;
        vm.expectRevert(AnomalyGatedBaseAssertion.SensitivityOutOfRange.selector);
        new CompositeTxEndHarness(c);

        c = _withDrain(_base());
        c.sensitivity = Sensitivity.MIN;
        new CompositeTxEndHarness(c);

        c = _withDrain(_base());
        c.sensitivity = Sensitivity.MAX;
        new CompositeTxEndHarness(c);
    }

    /// The baseline opt-in, anomalous: the bare gate blocks on the score alone.
    function test_bare_gate_blocks_when_anomalous() public {
        AnomalyCompositeAssertion.Config memory c = _base();
        c.bareGateBaseline = true;
        _register(c);
        vm.expectRevert();
        vault.poke();
    }

    /// `bareGateBaseline` alongside an enabled heuristic changes nothing: the leg set drives the
    /// disposition, so an anomalous tx with no damage stays in the alert cell.
    function test_baseline_flag_inert_when_heuristic_enabled() public {
        AnomalyCompositeAssertion.Config memory c = _withDrain(_base());
        c.bareGateBaseline = true;
        _register(c);
        vault.poke();
    }
}

/// @notice Proves the `_extra` leg participates in the operator alongside the generic heuristics.
contract TestAnomalyCompositeExtraLeg is CredibleTest, Test {
    uint8 internal constant LEVEL = Sensitivity.RECOMMENDED;
    uint256 internal constant DRAIN_FRAC_BPS = 250;
    uint256 internal constant SUPPLY = 100 ether;
    address internal constant SINK = address(0x5117);

    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        token.mint(address(vault), SUPPLY);
    }

    /// AND over {drain, extra}: block only when the reserve drains AND the protocol is unhealthy.
    function _config() internal view returns (AnomalyCompositeAssertion.Config memory c) {
        c.target = address(vault);
        c.sensitivity = LEVEL;
        c.requireAll = true;
        c.useDrain = true;
        c.outflowTarget = address(vault);
        c.outflowToken = address(token);
        c.outflowFracBps = DRAIN_FRAC_BPS;
    }

    function _register() internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(CompositeWithHealthTxEnd).creationCode, abi.encode(_config(), address(vault), true)
            ),
            fnSelector: AnomalyCompositeAssertion.assertComposite.selector
        });
    }

    /// Anomalous, draining, AND unhealthy: the extra leg corroborates so the AND blocks.
    function test_extra_leg_blocks_when_unhealthy() public {
        _register();
        vm.expectRevert();
        vault.drainWithFlag(SINK, 90 ether, false);
    }

    /// Anomalous and draining but the protocol stays healthy: the extra leg is silent, AND passes.
    function test_extra_leg_passes_when_healthy() public {
        _register();
        vault.drainWithFlag(SINK, 90 ether, true);
    }
}

/// @notice Regression coverage for the oracle leg: the query is an arg-taking reader
/// (`getAssetPrice(address)`), the shape a bare `bytes4` selector could not encode.
contract TestAnomalyCompositeOracleLeg is CredibleTest, Test {
    uint8 internal constant LEVEL = Sensitivity.RECOMMENDED;
    uint256 internal constant ORACLE_TOL_BPS = 200; // 2%
    address internal constant ASSET = address(0xA55E7);
    uint256 internal constant BASE_PRICE = 1000e8;

    MockERC20 internal token;
    Vault internal vault;
    MockOracle internal oracle;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        oracle = new MockOracle();
        oracle.setPrice(ASSET, BASE_PRICE);
    }

    /// OR over {oracle} only: block iff the oracle answer leaves tolerance across the transaction.
    function _config() internal view returns (AnomalyCompositeAssertion.Config memory c) {
        c.target = address(vault);
        c.sensitivity = LEVEL;
        c.useOracle = true;
        c.oracle = address(oracle);
        c.oracleQuery = abi.encodeWithSignature("getAssetPrice(address)", ASSET);
        c.oracleToleranceBps = ORACLE_TOL_BPS;
    }

    function _register() internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(type(CompositeTxEndHarness).creationCode, abi.encode(_config())),
            fnSelector: AnomalyCompositeAssertion.assertComposite.selector
        });
    }

    /// Anomalous and the oracle jumps 10% (past the 2% tolerance): the oracle leg corroborates, block.
    function test_oracle_leg_blocks_on_deviation() public {
        _register();
        vm.expectRevert();
        vault.moveOracle(address(oracle), ASSET, 1100e8);
    }

    /// Anomalous but the oracle stays within tolerance (+1%): the leg is silent, pass (exclusive set).
    function test_oracle_leg_passes_within_tolerance() public {
        _register();
        vault.moveOracle(address(oracle), ASSET, 1010e8);
    }
}

/// @notice Coverage for the accounting leg: block when the ERC4626 share price moves beyond
/// tolerance across the transaction.
contract TestAnomalyCompositeAccountingLeg is CredibleTest, Test {
    uint8 internal constant LEVEL = Sensitivity.RECOMMENDED;
    uint256 internal constant SHARE_TOL_BPS = 200; // 2%

    MockERC20 internal token;
    Vault internal vault;
    MockVault4626 internal vault4626;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        vault4626 = new MockVault4626(1000 ether, 1000 ether); // share price 1.0
    }

    /// OR over {accounting} only: block iff the share price leaves tolerance across the transaction.
    function _config() internal view returns (AnomalyCompositeAssertion.Config memory c) {
        c.target = address(vault);
        c.sensitivity = LEVEL;
        c.useAccounting = true;
        c.accountingVault = address(vault4626);
        c.shareToleranceBps = SHARE_TOL_BPS;
    }

    function _register() internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(type(CompositeTxEndHarness).creationCode, abi.encode(_config())),
            fnSelector: AnomalyCompositeAssertion.assertComposite.selector
        });
    }

    /// Anomalous and the share price jumps 10% (past the 2% tolerance): the leg corroborates, block.
    function test_accounting_leg_blocks_on_deviation() public {
        _register();
        vm.expectRevert();
        vault.moveSharePrice(address(vault4626), 1100 ether);
    }

    /// Anomalous but the share price stays within tolerance (+1%): the leg is silent, pass.
    function test_accounting_leg_passes_within_tolerance() public {
        _register();
        vault.moveSharePrice(address(vault4626), 1010 ether);
    }
}
