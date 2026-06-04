// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CapRedemptionGateAssertion} from "../src/CapRedemptionGateAssertion.sol";

contract MockCapVault {
    mapping(address => uint256) public loaned;

    function borrow(address asset, uint256 amount, address receiver) external {
        ERC20Mock(asset).transfer(receiver, amount);
    }

    function setLoaned(address asset, uint256 amount) external {
        loaned[asset] = amount;
    }
}

/// @notice Exposes the shipped assertion's internal tiered-gate decision so the threshold and
///         precedence logic can be exercised directly. The selector-detection path itself relies
///         on the `matchingCalls` precompile, which is not available in the local `pcl test`
///         harness, so the production decision is unit-tested here against simulated detection flags.
contract CapRedemptionGateHarness is CapRedemptionGateAssertion {
    constructor(address asset_) CapRedemptionGateAssertion(asset_, address(0), address(0), address(0), address(0)) {}

    function gateViolation(uint256 currentBps, bool borrowPresent, bool redemptionPresent, bool investPresent)
        external
        pure
        returns (string memory)
    {
        return _gateViolation(currentBps, borrowPresent, redemptionPresent, investPresent);
    }
}

contract CapRedemptionGateAssertionTest is Test, CredibleTest {
    ERC20Mock internal asset;
    MockCapVault internal vault;
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        asset = new ERC20Mock();
        vault = new MockCapVault();
        asset.mint(address(vault), 100 ether);
    }

    function _arm() internal {
        bytes memory createData = abi.encodePacked(
            type(CapRedemptionGateAssertion).creationCode,
            abi.encode(address(asset), address(0), address(0), address(0), address(0))
        );
        cl.assertion(address(vault), createData, CapRedemptionGateAssertion.assertCapRedemptionGate.selector);
    }

    function testSmallBorrowOutflowPassesBelowGateTier() public {
        _arm();
        vault.borrow(address(asset), 1 ether, receiver);
    }

    function testAssertionDeploysWithWatchedAsset() public {
        CapRedemptionGateAssertion assertion =
            new CapRedemptionGateAssertion(address(asset), address(0), address(0), address(0), address(0));
        assertTrue(address(assertion) != address(0));
    }

    // --- Tiered-gate decision coverage --------------------------------------------------
    // The end-to-end blocking paths in `assertCapRedemptionGate` route through the
    // `matchingCalls` precompile, which the local `pcl test` harness does not implement, so the
    // tier thresholds and precedence are validated directly against the shipped decision function.

    function testGateAllowsBelowBorrowTier() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        // Just under the 15% tier: nothing is blocked even when every gated call is present.
        assertEq(gate.gateViolation(1_499, true, true, true), "");
    }

    function testGateBlocksBorrowAtTier2() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        assertEq(gate.gateViolation(1_500, true, false, false), "CapGate: borrow disabled");
    }

    function testGateAllowsRedemptionBetweenBorrowAndRedemptionTiers() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        // 20% outflow trips the borrow tier but not the 30% redemption tier.
        assertEq(gate.gateViolation(2_000, false, true, false), "");
    }

    function testGateBlocksRedemptionAtTier3() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        assertEq(gate.gateViolation(3_000, false, true, false), "CapGate: redemption capacity reached");
    }

    function testGateAllowsInvestBelowHaltTier() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        // investAll stays allowed until the 50% halt tier, even at the redemption tier.
        assertEq(gate.gateViolation(3_000, false, false, true), "");
    }

    function testGateBlocksInvestAtHaltTier() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        assertEq(gate.gateViolation(5_000, false, false, true), "CapGate: invest disabled");
    }

    function testGateBorrowTakesPrecedenceOverRedemption() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        // With borrow + redemption both gated above the redemption tier, borrow blocks first.
        assertEq(gate.gateViolation(3_500, true, true, false), "CapGate: borrow disabled");
    }

    function testGateRedemptionTakesPrecedenceOverInvest() public {
        CapRedemptionGateHarness gate = new CapRedemptionGateHarness(address(asset));
        // Above the halt tier with redemption + invest gated, redemption blocks before invest.
        assertEq(gate.gateViolation(5_000, false, true, true), "CapGate: redemption capacity reached");
    }
}
