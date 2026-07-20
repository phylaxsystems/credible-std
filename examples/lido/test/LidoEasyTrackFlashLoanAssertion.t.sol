// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {LidoEasyTrackFlashLoanAssertion} from "../src/LidoEasyTrackFlashLoanAssertion.sol";
import {MockERC20} from "./LidoMocks.sol";
import {MockEasyTrack, MockFlashGovAttacker, MockHonestObjector} from "./LidoGovMocks.sol";

contract LidoEasyTrackFlashLoanAssertionTest is Test, CredibleTest {
    MockERC20 internal ldo;
    MockEasyTrack internal gov;
    MockFlashGovAttacker internal attacker;
    MockHonestObjector internal honest;

    address internal lender = makeAddr("flashLender");

    uint256 internal constant MOTION_ID = 1;
    uint256 internal constant LOAN = 5_000_000 ether; // enough LDO to clear an objection threshold

    function setUp() public {
        ldo = new MockERC20("Lido DAO Token", "LDO", 18);
        gov = new MockEasyTrack(ldo);
        attacker = new MockFlashGovAttacker();
        honest = new MockHonestObjector();
    }

    function _selectors() internal pure returns (bytes4[] memory sels) {
        sels = new bytes4[](1);
        sels[0] = MockEasyTrack.objectToMotion.selector;
    }

    function _arm(bytes4 fn, uint256 maxIntraTxAcquired) internal {
        bytes memory createData = abi.encodePacked(
            type(LidoEasyTrackFlashLoanAssertion).creationCode,
            abi.encode(address(gov), address(ldo), maxIntraTxAcquired, _selectors())
        );
        cl.assertion(address(gov), createData, fn);
    }

    // --- Primary layer: balance delta around the governance call -----------

    function testFlashLoanedObjectionTripsBalanceLayer() public {
        // Lender funds the flash loan; attacker holds no LDO at transaction start.
        ldo.setBalance(lender, LOAN);
        vm.prank(lender);
        ldo.approve(address(attacker), LOAN);

        _arm(LidoEasyTrackFlashLoanAssertion.assertNoFlashLoanedVotingPower.selector, 0);

        // borrow → object with borrowed power → repay, all in one transaction.
        vm.expectRevert(bytes("LidoGov: flash-loaned voting power"));
        attacker.flashObject(gov, ldo, lender, MOTION_ID, LOAN);
    }

    function testHonestObjectionPassesBalanceLayer() public {
        // Honest objector durably holds LDO before the transaction.
        ldo.setBalance(address(honest), LOAN);

        _arm(LidoEasyTrackFlashLoanAssertion.assertNoFlashLoanedVotingPower.selector, 0);

        honest.object(gov, MOTION_ID);
    }

    function testSmallSameTxTopUpAllowedByTolerance() public {
        // Honest holder already holds power; a tiny same-tx top-up is within tolerance.
        ldo.setBalance(lender, 1 ether);
        vm.prank(lender);
        ldo.approve(address(attacker), 1 ether);

        _arm(LidoEasyTrackFlashLoanAssertion.assertNoFlashLoanedVotingPower.selector, 1 ether);

        // Borrows exactly the tolerance, so the increase is allowed.
        attacker.flashObject(gov, ldo, lender, MOTION_ID, 1 ether);
    }

    function testHistoricalMotionIgnoresCurrentBalanceTopUp() public {
        gov.setMotionSnapshotBlock(MOTION_ID, 1);
        vm.roll(2);
        ldo.setBalance(lender, LOAN);
        vm.prank(lender);
        ldo.approve(address(attacker), LOAN);

        _arm(LidoEasyTrackFlashLoanAssertion.assertNoFlashLoanedVotingPower.selector, 0);

        // The real motion reads an older MiniMe snapshot. Tokens acquired now cannot affect its
        // objection weight, so the external guard must not compare live balances for this call.
        attacker.flashObject(gov, ldo, lender, MOTION_ID, LOAN);
    }

    // --- Corroborating layer: same-tx gov-token inflow ---------------------

    function retiredGrossInflowPolicyFlashLoanedObjectionTrips() public {
        ldo.setBalance(lender, LOAN);
        vm.prank(lender);
        ldo.approve(address(attacker), LOAN);

        _arm(LidoEasyTrackFlashLoanAssertion.assertNoSameTxGovTokenInflow.selector, 0);

        // A flash loan nets to zero for the attacker, but the gross inbound leg trips this layer.
        vm.expectRevert(bytes("LidoGov: same-tx governance token inflow"));
        attacker.flashObject(gov, ldo, lender, MOTION_ID, LOAN);
    }

    function retiredGrossInflowPolicyHonestObjectionPasses() public {
        ldo.setBalance(address(honest), LOAN);

        _arm(LidoEasyTrackFlashLoanAssertion.assertNoSameTxGovTokenInflow.selector, 0);

        honest.object(gov, MOTION_ID);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroGovernanceContract() public {
        vm.expectRevert(bytes("LidoGov: zero governance contract"));
        new LidoEasyTrackFlashLoanAssertion(address(0), address(ldo), 0, _selectors());
    }

    function testRejectsZeroGovernanceToken() public {
        vm.expectRevert(bytes("LidoGov: zero governance token"));
        new LidoEasyTrackFlashLoanAssertion(address(gov), address(0), 0, _selectors());
    }

    function testRejectsEmptySelectors() public {
        vm.expectRevert(bytes("LidoGov: protect only objectToMotion"));
        new LidoEasyTrackFlashLoanAssertion(address(gov), address(ldo), 0, new bytes4[](0));
    }

    function testRejectsZeroSelector() public {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = bytes4(0);
        vm.expectRevert(bytes("LidoGov: unsupported protected selector"));
        new LidoEasyTrackFlashLoanAssertion(address(gov), address(ldo), 0, sels);
    }

    function testDeploys() public {
        LidoEasyTrackFlashLoanAssertion assertion =
            new LidoEasyTrackFlashLoanAssertion(address(gov), address(ldo), 0, _selectors());
        assertTrue(address(assertion) != address(0));
    }
}
