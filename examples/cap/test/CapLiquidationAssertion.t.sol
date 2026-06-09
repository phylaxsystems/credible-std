// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CapLiquidationAssertion} from "../src/CapLiquidationAssertion.sol";

/// @notice Vault stand-in exposing the claimable-backing view the assertion reads.
contract MockVault {
    mapping(address => uint256) public availableBalance;

    function setAvailable(address asset, uint256 amount) external {
        availableBalance[asset] = amount;
    }
}

/// @notice Minimal Cap `Lender` stand-in. `liquidate` reproduces the real settlement shape:
///         restaker interest is first realized out of the vault, then principal is repaid back
///         into it while the agent's debt is burned. Mode knobs reproduce two failure modes:
///         seizing collateral without repaying debt, and draining the vault past realized interest.
contract MockLender {
    enum Mode {
        Honest,
        NoRepay,
        DrainBacking
    }

    Mode public mode;
    MockVault public immutable vault;

    mapping(address => mapping(address => uint256)) public debtOf;
    mapping(address => mapping(address => uint256)) public realizedOf;

    constructor(MockVault vault_) {
        vault = vault_;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    /// @dev Seed a liquidatable position: agent owes `debt_`, the vault holds `avail_` claimable
    ///      backing, and the next repay will realize `realized_` of restaker interest.
    function seed(address agent, address asset, uint256 debt_, uint256 realized_, uint256 avail_) external {
        debtOf[agent][asset] = debt_;
        realizedOf[agent][asset] = realized_;
        vault.setAvailable(asset, avail_);
    }

    function debt(address agent, address asset) external view returns (uint256) {
        return debtOf[agent][asset];
    }

    function maxRestakerRealization(address agent, address asset) external view returns (uint256, uint256) {
        return (realizedOf[agent][asset], 0);
    }

    function reservesData(address) external view returns (uint256, address, address, address, uint8, bool, uint256) {
        return (0, address(vault), address(0), address(0), 6, false, 0);
    }

    function liquidate(address agent, address asset, uint256 amount, uint256) external returns (uint256 repaid) {
        // Realize restaker interest by borrowing from the vault (lowers claimable backing).
        uint256 realized = realizedOf[agent][asset];
        uint256 avail = vault.availableBalance(asset) - realized;
        realizedOf[agent][asset] = 0;

        uint256 owed = debtOf[agent][asset];
        repaid = amount > owed ? owed : amount;

        if (mode == Mode.NoRepay) {
            // Collateral seized, but debt left untouched and nothing returned to the vault.
            vault.setAvailable(asset, avail);
            return 0;
        }

        debtOf[agent][asset] = owed - repaid;

        if (mode == Mode.DrainBacking) {
            // Debt burned, but proceeds siphoned out of the vault instead of restored as backing.
            avail = avail > repaid ? avail - repaid : 0;
        } else {
            // Honest: repaid principal flows back into the vault.
            avail += repaid;
        }

        vault.setAvailable(asset, avail);
    }
}

contract CapLiquidationAssertionTest is Test, CredibleTest {
    MockVault internal vault;
    MockLender internal lender;

    address internal usdc = makeAddr("usdc");
    address internal agent = makeAddr("agent");
    address internal liquidator = makeAddr("liquidator");

    function setUp() public {
        vault = new MockVault();
        lender = new MockLender(vault);
        // Agent owes 100 USDC; vault holds 1000 claimable backing; 2 USDC restaker interest accrued.
        lender.seed(agent, usdc, 100e6, 2e6, 1_000e6);
    }

    function _armReducesDebt() internal {
        bytes memory createData = abi.encodePacked(type(CapLiquidationAssertion).creationCode);
        cl.assertion(address(lender), createData, CapLiquidationAssertion.assertLiquidationReducesDebt.selector);
    }

    function _armRetainsBacking() internal {
        bytes memory createData = abi.encodePacked(type(CapLiquidationAssertion).creationCode);
        cl.assertion(address(lender), createData, CapLiquidationAssertion.assertLiquidationRetainsBacking.selector);
    }

    function testHonestLiquidationReducesDebt() public {
        _armReducesDebt();
        vm.prank(liquidator);
        lender.liquidate(agent, usdc, 60e6, 0);
    }

    function testNoRepayLiquidationTrips() public {
        lender.setMode(MockLender.Mode.NoRepay);
        _armReducesDebt();
        vm.expectRevert(bytes("CapLiquidation: debt not reduced"));
        vm.prank(liquidator);
        lender.liquidate(agent, usdc, 60e6, 0);
    }

    function testZeroAmountLiquidationIgnored() public {
        _armReducesDebt();
        // No value moves; the debt-reduction check skips it rather than false-tripping.
        vm.prank(liquidator);
        lender.liquidate(agent, usdc, 0, 0);
    }

    function testHonestLiquidationRetainsBacking() public {
        _armRetainsBacking();
        vm.prank(liquidator);
        lender.liquidate(agent, usdc, 60e6, 0);
    }

    function testDrainBackingTrips() public {
        lender.setMode(MockLender.Mode.DrainBacking);
        _armRetainsBacking();
        vm.expectRevert(bytes("CapLiquidation: backing drained by liquidation"));
        vm.prank(liquidator);
        lender.liquidate(agent, usdc, 60e6, 0);
    }

    function testDeploys() public {
        CapLiquidationAssertion assertion = new CapLiquidationAssertion();
        assertTrue(address(assertion) != address(0));
    }
}
