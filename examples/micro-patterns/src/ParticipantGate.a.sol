// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface ISensitiveToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

interface IParticipantOracle {
    function isBlocked(address account) external view returns (bool);
}

/// @notice Extract participants from sensitive calls and block listed accounts.
/// @dev Protects against blocked participants reaching sensitive paths indirectly:
///      - a blocked transaction sender using an unblocked intermediate caller;
///      - a blocked immediate caller forwarding someone else's transfer;
///      - selector-specific participants such as `from`, `to`, mint receiver, or burn source being blocked.
contract ParticipantGateAssertion is Assertion {
    IParticipantOracle public immutable ORACLE;

    constructor(IParticipantOracle oracle_) {
        registerAssertionSpec(AssertionSpec.Reshiram);
        ORACLE = oracle_;
    }

    function triggers() external view override {
        registerFnCallTrigger(this.assertAllowedParticipants.selector, ISensitiveToken.transfer.selector);
        registerFnCallTrigger(this.assertAllowedParticipants.selector, ISensitiveToken.transferFrom.selector);
        registerFnCallTrigger(this.assertAllowedParticipants.selector, ISensitiveToken.mint.selector);
        registerFnCallTrigger(this.assertAllowedParticipants.selector, ISensitiveToken.burn.selector);
    }

    function assertAllowedParticipants() external view {
        PhEvm.TriggerContext memory ctx = ph.context();

        // Failure scenario: a blocked EOA enters through a router or relayer.
        _assertAllowed(ph.getTxObject().from);

        // Failure scenario: a blocked contract or delegated operator is the direct caller.
        _assertAllowed(_triggerCaller(ctx));

        if (ctx.selector == ISensitiveToken.transfer.selector || ctx.selector == ISensitiveToken.mint.selector) {
            // Failure scenario: assets are sent or minted to a blocked recipient.
            _assertAllowed(_addressArg(ph.callinputAt(ctx.callStart), 0));
            return;
        }

        if (ctx.selector == ISensitiveToken.transferFrom.selector) {
            // Failure scenario: transferFrom moves funds from or to a blocked participant.
            _assertAllowed(_addressArg(ph.callinputAt(ctx.callStart), 0));
            _assertAllowed(_addressArg(ph.callinputAt(ctx.callStart), 1));
            return;
        }

        if (ctx.selector == ISensitiveToken.burn.selector) {
            // Failure scenario: a burn path is used to process a blocked source account.
            _assertAllowed(_addressArg(ph.callinputAt(ctx.callStart), 0));
        }
    }

    function _triggerCaller(PhEvm.TriggerContext memory ctx) private view returns (address) {
        PhEvm.TriggerCall[] memory calls = _matchingCalls(ph.getAssertionAdopter(), ctx.selector, 16);
        for (uint256 i; i < calls.length; ++i) {
            if (calls[i].callId == ctx.callStart) return calls[i].caller;
        }
        revert("trigger call not found");
    }

    function _assertAllowed(address account) private view {
        if (account != address(0)) require(!ORACLE.isBlocked(account), "blocked participant");
    }

    function _addressArg(bytes memory input, uint256 argIndex) private pure returns (address account) {
        uint256 offset = 4 + argIndex * 32;
        require(input.length >= offset + 32, "malformed calldata");
        assembly {
            account := shr(96, mload(add(add(input, 0x20), offset)))
        }
    }
}
