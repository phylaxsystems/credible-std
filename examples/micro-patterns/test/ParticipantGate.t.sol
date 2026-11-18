// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";
import {ParticipantGateAssertion, IParticipantOracle} from "../src/ParticipantGate.a.sol";

contract ParticipantOracleMock is IParticipantOracle {
    mapping(address => bool) public isBlocked;

    function blockAccount(address account) external {
        isBlocked[account] = true;
    }
}

/// @dev Minimal call surface: screening is independent of balances and token authorization.
contract SensitiveTokenMock {
    function transfer(address, uint256) external returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        return true;
    }

    function mint(address, uint256) external {}

    function burn(address, uint256) external {}
}

contract ParticipantGateTest is Test, CredibleTest {
    ParticipantOracleMock internal oracle;
    SensitiveTokenMock internal token;
    address internal blocked = address(bytes20(hex"1234567890abcdef1234567890abcdef12345678"));
    address internal allowed = address(bytes20(hex"9876543210abcdef9876543210abcdef98765432"));

    function setUp() public {
        oracle = new ParticipantOracleMock();
        token = new SensitiveTokenMock();
        oracle.blockAccount(blocked);
    }

    function _arm() internal {
        cl.assertion(
            address(token),
            abi.encodePacked(type(ParticipantGateAssertion).creationCode, abi.encode(oracle)),
            ParticipantGateAssertion.assertAllowedParticipants.selector
        );
    }

    function testAllowedTransferPasses() public {
        _arm();
        assertTrue(token.transfer(allowed, 1));
    }

    function testBlockedTransferRecipientReverts() public {
        _arm();
        vm.expectRevert("blocked participant");
        token.transfer(blocked, 1);
    }

    function testBlockedTransferFromSourceReverts() public {
        _arm();
        vm.expectRevert("blocked participant");
        token.transferFrom(blocked, allowed, 1);
    }

    function testBlockedTransferFromRecipientReverts() public {
        _arm();
        vm.expectRevert("blocked participant");
        token.transferFrom(allowed, blocked, 1);
    }

    function testBlockedMintReceiverReverts() public {
        _arm();
        vm.expectRevert("blocked participant");
        token.mint(blocked, 1);
    }

    function testBlockedBurnSourceReverts() public {
        _arm();
        vm.expectRevert("blocked participant");
        token.burn(blocked, 1);
    }

    function testShiftedAddressDoesNotBlockAllowedRecipient() public {
        oracle.blockAccount(address(uint160(allowed) >> 96));
        _arm();
        assertTrue(token.transfer(allowed, 1));
    }

    function testBlockedCallerReverts() public {
        oracle.blockAccount(address(this));
        _arm();
        vm.expectRevert("blocked participant");
        token.transfer(allowed, 1);
    }

    function testFuzzBlockedRecipientReverts(address recipient) public {
        vm.assume(recipient != address(0));
        oracle.blockAccount(recipient);
        _arm();
        vm.expectRevert("blocked participant");
        token.transfer(recipient, 1);
    }
}
