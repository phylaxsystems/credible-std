// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";
import {Sensitivity} from "credible-std/Sensitivity.sol";
import {AnomalyGatedBaseAssertion} from "credible-std/protection/anomaly/AnomalyGatedBaseAssertion.sol";
import {AnomalyGatedOutflowAssertion} from "credible-std/protection/anomaly/AnomalyGatedOutflowAssertion.sol";
import {AnomalyGatedUpgradeAssertion} from "credible-std/protection/anomaly/AnomalyGatedUpgradeAssertion.sol";
import {AnomalyGatedAccountingAssertion} from "credible-std/protection/anomaly/AnomalyGatedAccountingAssertion.sol";
import {AnomalyGatedOracleAssertion} from "credible-std/protection/anomaly/AnomalyGatedOracleAssertion.sol";
import {MockERC20, MockOracle, MockVault4626, Vault} from "./AnomalyTestMocks.sol";

// Single-heuristic mixin coverage. Each mixin body runs only once the anomaly trigger has fired,
// so what these prove is the damage half: block on a corroborated check, and the exclusive-set pass
// when nothing corroborates.
//
// Released pcl has no anomaly precompile, so the harnesses fire from a tx-end trigger standing in
// for the anomaly trigger. Whether that trigger fires at a given sensitivity level is the
// executor's decision, tested in its own selection suite.

/// @notice The outflow mixin fired by a tx-end trigger standing in for the anomaly trigger.
contract OutflowTxEndHarness is AnomalyGatedOutflowAssertion {
    constructor(address target_, address token_, uint256 fracBps)
        AnomalyGatedBaseAssertion(target_, Sensitivity.RECOMMENDED)
        AnomalyGatedOutflowAssertion(target_, token_, fracBps)
    {}

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertAnomalousOutflow.selector);
    }
}

/// @notice The upgrade mixin fired by a tx-end trigger standing in for the anomaly trigger.
contract UpgradeTxEndHarness is AnomalyGatedUpgradeAssertion {
    constructor(address target_, address upgradeTarget_, bytes32 ownerSlot_)
        AnomalyGatedBaseAssertion(target_, Sensitivity.RECOMMENDED)
        AnomalyGatedUpgradeAssertion(upgradeTarget_, ownerSlot_)
    {}

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertAnomalousUpgrade.selector);
    }
}

/// @notice The accounting mixin fired by a tx-end trigger standing in for the anomaly trigger.
contract AccountingTxEndHarness is AnomalyGatedAccountingAssertion {
    constructor(address target_, address vault4626_, uint256 toleranceBps)
        AnomalyGatedBaseAssertion(target_, Sensitivity.RECOMMENDED)
        AnomalyGatedAccountingAssertion(vault4626_, toleranceBps)
    {}

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertAnomalousAccounting.selector);
    }
}

/// @notice The oracle mixin fired by a tx-end trigger standing in for the anomaly trigger.
contract OracleTxEndHarness is AnomalyGatedOracleAssertion {
    constructor(address target_, address oracle_, bytes memory query, uint256 toleranceBps)
        AnomalyGatedBaseAssertion(target_, Sensitivity.RECOMMENDED)
        AnomalyGatedOracleAssertion(oracle_, query, toleranceBps)
    {}

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertAnomalousOracle.selector);
    }
}

/// @notice The README's `MyGuard` shape: two mixins inherited together, composing as OR since any
/// revert invalidates. Triggers moved to tx-end, as above.
contract MyGuardTxEndHarness is AnomalyGatedOutflowAssertion, AnomalyGatedUpgradeAssertion {
    constructor(address target_, address token_)
        AnomalyGatedBaseAssertion(target_, Sensitivity.RECOMMENDED)
        AnomalyGatedOutflowAssertion(target_, token_, 250)
        AnomalyGatedUpgradeAssertion(address(0), bytes32(0))
    {}

    function triggers() external view override {
        // Stands in for the anomaly trigger, which in production fires this selector only when
        // the score clears the sensitivity level.
        registerTxEndTrigger(this.assertAnomalousOutflow.selector);
        registerTxEndTrigger(this.assertAnomalousUpgrade.selector);
    }
}

/// @notice The drain mixin: block on a corroborated drain, exclusive-set pass below the fraction.
contract TestAnomalyGatedOutflowAssertion is CredibleTest, Test {
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

    function _register() internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(OutflowTxEndHarness).creationCode, abi.encode(address(vault), address(token), DRAIN_FRAC_BPS)
            ),
            fnSelector: AnomalyGatedOutflowAssertion.assertAnomalousOutflow.selector
        });
    }

    /// Anomalous and the tx drains 90% (past the 2.5% fraction): block.
    function test_blocks_anomalous_drain() public {
        _register();
        vm.expectRevert();
        vault.drain(SINK, 90 ether);
    }

    /// Anomalous but the drain stays under the fraction (1%): the exclusive set, no revert.
    function test_passes_drain_below_fraction() public {
        _register();
        vault.drain(SINK, 1 ether);
    }

    /// A zero token address reverts at deploy: the leg would read a zero balance and stay inert.
    function test_zero_token_reverts_at_deploy() public {
        vm.expectRevert(AnomalyGatedBaseAssertion.HeuristicMisconfigured.selector);
        new OutflowTxEndHarness(address(vault), address(0), DRAIN_FRAC_BPS);
    }

    /// A fraction above 10_000 reverts at deploy: net outflow is capped by the pre-transaction
    /// balance, so the leg could never corroborate. The 10_000 boundary itself deploys.
    function test_fraction_above_cap_reverts_at_deploy() public {
        vm.expectRevert(AnomalyGatedBaseAssertion.HeuristicMisconfigured.selector);
        new OutflowTxEndHarness(address(vault), address(token), 10_001);

        new OutflowTxEndHarness(address(vault), address(token), 10_000);
    }
}

/// @notice The upgrade mixin's disposition, including the named owner slot.
contract TestAnomalyGatedUpgradeAssertion is CredibleTest, Test {
    address internal constant IMPL = address(0x1);
    address internal constant SINK = address(0x5117);

    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
    }

    function _register(bytes32 ownerSlot) internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(UpgradeTxEndHarness).creationCode, abi.encode(address(vault), address(0), ownerSlot)
            ),
            fnSelector: AnomalyGatedUpgradeAssertion.assertAnomalousUpgrade.selector
        });
    }

    /// Anomalous and the tx rewrites the EIP-1967 implementation slot: block.
    function test_blocks_anomalous_upgrade() public {
        _register(bytes32(0));
        vm.expectRevert();
        vault.upgradeTo(IMPL);
    }

    /// Anomalous and the tx rewrites the EIP-1967 admin slot: block.
    function test_blocks_anomalous_admin_change() public {
        _register(bytes32(0));
        vm.expectRevert();
        vault.changeAdmin(SINK);
    }

    /// Anomalous and the tx rewrites the named owner slot: block.
    function test_blocks_anomalous_owner_slot_write() public {
        _register(vault.OWNER_SLOT());
        vm.expectRevert();
        vault.setOwner(SINK);
    }

    /// Anomalous but no watched slot changes: the exclusive set, no revert.
    function test_passes_without_slot_change() public {
        _register(vault.OWNER_SLOT());
        vault.poke();
    }
}

/// @notice The accounting mixin's disposition over an ERC4626 share-price move.
contract TestAnomalyGatedAccountingAssertion is CredibleTest, Test {
    uint256 internal constant SHARE_TOL_BPS = 200; // 2%

    MockERC20 internal token;
    Vault internal vault;
    MockVault4626 internal vault4626;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        vault4626 = new MockVault4626(1000 ether, 1000 ether); // share price 1.0
    }

    function _register() internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(AccountingTxEndHarness).creationCode, abi.encode(address(vault), address(vault4626), SHARE_TOL_BPS)
            ),
            fnSelector: AnomalyGatedAccountingAssertion.assertAnomalousAccounting.selector
        });
    }

    /// Anomalous and the share price jumps 10% (past the 2% tolerance): block.
    function test_blocks_anomalous_share_price_move() public {
        _register();
        vm.expectRevert();
        vault.moveSharePrice(address(vault4626), 1100 ether);
    }

    /// Anomalous but the share price stays within tolerance (+1%): the exclusive set, no revert.
    function test_passes_within_tolerance() public {
        _register();
        vault.moveSharePrice(address(vault4626), 1010 ether);
    }

    /// A zero vault address reverts at deploy: the leg would skip the read and stay inert.
    function test_zero_vault_reverts_at_deploy() public {
        vm.expectRevert(AnomalyGatedBaseAssertion.HeuristicMisconfigured.selector);
        new AccountingTxEndHarness(address(vault), address(0), SHARE_TOL_BPS);
    }
}

/// @notice The oracle mixin's disposition over a deviating asset-priced feed.
contract TestAnomalyGatedOracleAssertion is CredibleTest, Test {
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

    function _register() internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(OracleTxEndHarness).creationCode,
                abi.encode(
                    address(vault),
                    address(oracle),
                    abi.encodeWithSignature("getAssetPrice(address)", ASSET),
                    ORACLE_TOL_BPS
                )
            ),
            fnSelector: AnomalyGatedOracleAssertion.assertAnomalousOracle.selector
        });
    }

    /// Anomalous and the oracle jumps 10% (past the 2% tolerance): block.
    function test_blocks_anomalous_oracle_move() public {
        _register();
        vm.expectRevert();
        vault.moveOracle(address(oracle), ASSET, 1100e8);
    }

    /// Anomalous but the oracle stays within tolerance (+1%): the exclusive set, no revert.
    function test_passes_within_tolerance() public {
        _register();
        vault.moveOracle(address(oracle), ASSET, 1010e8);
    }

    /// An empty oracle query reverts at deploy: the read would error on every anomalous tx and
    /// falsely invalidate.
    function test_empty_query_reverts_at_deploy() public {
        vm.expectRevert(AnomalyGatedBaseAssertion.HeuristicMisconfigured.selector);
        new OracleTxEndHarness(address(vault), address(oracle), "", ORACLE_TOL_BPS);
    }
}

/// @notice The README's `MyGuard` diamond compiles and each inherited leg blocks on its own damage.
contract TestMyGuardComposition is CredibleTest, Test {
    uint256 internal constant SUPPLY = 100 ether;
    address internal constant SINK = address(0x5117);
    address internal constant IMPL = address(0x1);

    MockERC20 internal token;
    Vault internal vault;

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(token);
        token.mint(address(vault), SUPPLY);
    }

    function _register(bytes4 fnSelector) internal {
        cl.assertion({
            adopter: address(vault),
            createData: abi.encodePacked(
                type(MyGuardTxEndHarness).creationCode, abi.encode(address(vault), address(token))
            ),
            fnSelector: fnSelector
        });
    }

    /// Anomalous and the tx drains: the outflow leg blocks.
    function test_drain_leg_blocks() public {
        _register(AnomalyGatedOutflowAssertion.assertAnomalousOutflow.selector);
        vm.expectRevert();
        vault.drain(SINK, 90 ether);
    }

    /// Anomalous and the tx upgrades: the upgrade leg blocks.
    function test_upgrade_leg_blocks() public {
        _register(AnomalyGatedUpgradeAssertion.assertAnomalousUpgrade.selector);
        vm.expectRevert();
        vault.upgradeTo(IMPL);
    }
}
