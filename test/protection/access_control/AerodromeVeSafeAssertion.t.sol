// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {AerodromeVeSafeAssertion} from "../../../src/protection/access_control/examples/AerodromeVeSafeAssertion.sol";

import {
    MockAerodromeVeSafeGovernor,
    MockAerodromeVeSafeVoter,
    MockAerodromeVeSafeVotingEscrow,
    MockNoopTarget,
    MockSafe
} from "../../fixtures/access_control/MockAerodromeVeSafe.sol";

/// @title AerodromeVeSafeAssertionTest
/// @notice cl.assertion-armed tests for Safe-scoped veAERO custody and governance denial checks.
contract AerodromeVeSafeAssertionTest is Test, CredibleTest {
    MockSafe internal safe;
    MockAerodromeVeSafeVotingEscrow internal ve;
    MockAerodromeVeSafeVoter internal voter;
    MockAerodromeVeSafeGovernor internal protocolGovernor;
    MockAerodromeVeSafeGovernor internal epochGovernor;
    MockNoopTarget internal noop;

    function setUp() public {
        safe = new MockSafe();
        ve = new MockAerodromeVeSafeVotingEscrow();
        voter = new MockAerodromeVeSafeVoter();
        protocolGovernor = new MockAerodromeVeSafeGovernor();
        epochGovernor = new MockAerodromeVeSafeGovernor();
        noop = new MockNoopTarget();
    }

    function _arm(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(AerodromeVeSafeAssertion).creationCode,
            abi.encode(address(safe), address(ve), address(voter), address(protocolGovernor), address(epochGovernor))
        );
        cl.assertion(address(safe), createData, fnSelector);
    }

    function testNoVeAeroApprovalOrTransferLogsPassesOnUnrelatedSafeTx() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroApprovalOrTransferLogs.selector);
        safe.execute(address(noop), abi.encodeCall(MockNoopTarget.ping, ()));
    }

    function testVeAeroApprovalLogTrips() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroApprovalOrTransferLogs.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: veAERO Approval emitted"));
        safe.execute(address(ve), abi.encodeCall(MockAerodromeVeSafeVotingEscrow.approve, (address(0xBEEF), 1)));
    }

    function testVeAeroApprovalForAllLogTrips() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroApprovalOrTransferLogs.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: veAERO ApprovalForAll emitted"));
        safe.execute(
            address(ve), abi.encodeCall(MockAerodromeVeSafeVotingEscrow.setApprovalForAll, (address(0xBEEF), true))
        );
    }

    function testVeAeroTransferLogTrips() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroApprovalOrTransferLogs.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: veAERO Transfer emitted"));
        safe.execute(
            address(ve),
            abi.encodeCall(MockAerodromeVeSafeVotingEscrow.transferFrom, (address(safe), address(0xBEEF), 1))
        );
    }

    function testNoVeAeroDelegationChangesPassesOnUnrelatedSafeTx() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroDelegationChanges.selector);
        safe.execute(address(noop), abi.encodeCall(MockNoopTarget.ping, ()));
    }

    function testVeAeroDelegateLogTrips() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroDelegationChanges.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: veAERO delegation changed"));
        safe.execute(address(ve), abi.encodeCall(MockAerodromeVeSafeVotingEscrow.delegate, (1, 2)));
    }

    function testNoCustodyOrVotingPowerCallsPassesOnNonSensitiveVeCall() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroCustodyOrVotingPowerCalls.selector);
        safe.execute(address(ve), abi.encodeCall(MockAerodromeVeSafeVotingEscrow.checkpoint, ()));
    }

    function testVeAeroUnlockPermanentCallTripsWithoutRestrictedLog() public {
        _arm(AerodromeVeSafeAssertion.assertNoVeAeroCustodyOrVotingPowerCalls.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: veAERO unlockPermanent call"));
        safe.execute(address(ve), abi.encodeCall(MockAerodromeVeSafeVotingEscrow.unlockPermanent, (1)));
    }

    function testVoterVoteCallTrips() public {
        address[] memory pools = new address[](1);
        uint256[] memory weights = new uint256[](1);
        pools[0] = address(0xCAFE);
        weights[0] = 1;

        _arm(AerodromeVeSafeAssertion.assertNoVeAeroCustodyOrVotingPowerCalls.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: Voter vote call"));
        safe.execute(address(voter), abi.encodeCall(MockAerodromeVeSafeVoter.vote, (1, pools, weights)));
    }

    function testNoGovernorVotesFromSafePassesOnUnrelatedSafeTx() public {
        _arm(AerodromeVeSafeAssertion.assertNoGovernorVotesFromSafe.selector);
        safe.execute(address(noop), abi.encodeCall(MockNoopTarget.ping, ()));
    }

    function testGovernorVoteCastBySafeTrips() public {
        _arm(AerodromeVeSafeAssertion.assertNoGovernorVotesFromSafe.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: Governor VoteCast by safe"));
        safe.execute(address(protocolGovernor), abi.encodeCall(MockAerodromeVeSafeGovernor.castVote, (1, 7, 1)));
    }

    function testGovernorVoteBySigSubmissionTripsEvenWhenVoterIsNotSafe() public {
        _arm(AerodromeVeSafeAssertion.assertNoGovernorVotesFromSafe.selector);
        vm.expectRevert(bytes("AerodromeVeSafe: Governor castVoteBySig call"));
        safe.execute(
            address(protocolGovernor),
            abi.encodeCall(MockAerodromeVeSafeGovernor.castVoteBySig, (1, 7, 1, 27, bytes32(0), bytes32(0)))
        );
    }
}
