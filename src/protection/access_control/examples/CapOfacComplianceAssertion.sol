// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../../Assertion.sol";
import {PhEvm} from "../../../PhEvm.sol";
import {AssertionSpec} from "../../../SpecRecorder.sol";
import {
    ICapAccessControlLike,
    ICapERC20Like,
    ICapERC4626Like,
    ICapLenderLike,
    ICapStabledropLike,
    ICapVaultLike,
    IOfacCompliancePrecompile
} from "./CapOfacComplianceInterfaces.sol";

/// @title CapOfacComplianceAssertion
/// @author Phylax Systems
/// @notice Example Cap assertion for blocking sanctioned participants from sensitive paths.
/// @dev This example assumes a hypothetical OFAC precompile at
///      `address(uint160(uint256(keccak256("OfacCompliancePrecompile"))))`.
///      The precompile is expected to expose `isListed(address) returns (bool listed)`.
///
///      Deploy this assertion against the Cap contract surface being protected:
///      - Vault: mint, burn, redeem, borrow, repay, rescue, insurance-fund updates
///      - Lender: borrow, repay, liquidation, restaker interest, interest receiver updates
///      - Stabledrop: claim, operator approvals, recovery
///      - AccessControl: grant/revoke access
///      - Cap ERC20 / StakedCap ERC4626 inherited transfer and share-entry/exit paths
contract CapOfacComplianceAssertion is Assertion {
    IOfacCompliancePrecompile internal constant OFAC =
        IOfacCompliancePrecompile(address(uint160(uint256(keccak256("OfacCompliancePrecompile")))));

    uint256 internal constant MAX_MATCHING_CALLS = 1024;

    constructor() {
        registerAssertionSpec(AssertionSpec.Experimental);
    }

    function triggers() external view override {
        _registerAccessControlTriggers();
        _registerErc20Triggers();
        _registerErc4626Triggers();
        _registerLenderTriggers();
        _registerStabledropTriggers();
        _registerVaultTriggers();
    }

    /// @notice Checks the triggering Cap operation does not involve a sanctioned participant.
    /// @dev Checks the transaction sender, immediate caller, and selector-specific account
    ///      arguments decoded from calldata. Fails when the hypothetical OFAC precompile reports
    ///      any participant address as listed.
    function assertOfacCompliantParticipants() external view {
        PhEvm.TriggerContext memory ctx = ph.context();
        bytes memory input = ph.callinputAt(ctx.callStart);

        _assertNotListed(ph.getTxObject().from);
        _assertNotListed(_triggeredCaller(ctx));
        _assertSelectorSpecificParticipants(ctx.selector, input);
    }

    function _registerAccessControlTriggers() internal view {
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapAccessControlLike.grantAccess.selector);
        registerFnCallTrigger(
            this.assertOfacCompliantParticipants.selector, ICapAccessControlLike.revokeAccess.selector
        );
    }

    function _registerErc20Triggers() internal view {
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC20Like.transfer.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC20Like.transferFrom.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC20Like.approve.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC20Like.permit.selector);
    }

    function _registerErc4626Triggers() internal view {
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC4626Like.deposit.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC4626Like.mint.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC4626Like.withdraw.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapERC4626Like.redeem.selector);
    }

    function _registerLenderTriggers() internal view {
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapLenderLike.borrow.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapLenderLike.repay.selector);
        registerFnCallTrigger(
            this.assertOfacCompliantParticipants.selector, ICapLenderLike.realizeRestakerInterest.selector
        );
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapLenderLike.openLiquidation.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapLenderLike.closeLiquidation.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapLenderLike.liquidate.selector);
        registerFnCallTrigger(
            this.assertOfacCompliantParticipants.selector, ICapLenderLike.setInterestReceiver.selector
        );
    }

    function _registerStabledropTriggers() internal view {
        registerFnCallTrigger(
            this.assertOfacCompliantParticipants.selector, ICapStabledropLike.approveOperator.selector
        );
        registerFnCallTrigger(
            this.assertOfacCompliantParticipants.selector, ICapStabledropLike.approveOperatorFor.selector
        );
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapStabledropLike.claim.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapStabledropLike.recoverERC20.selector);
    }

    function _registerVaultTriggers() internal view {
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapVaultLike.mint.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapVaultLike.burn.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapVaultLike.redeem.selector);
        // `borrow(address,uint256,address)` is already registered through the Lender surface.
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapVaultLike.repay.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapVaultLike.setInsuranceFund.selector);
        registerFnCallTrigger(this.assertOfacCompliantParticipants.selector, ICapVaultLike.rescueERC20.selector);
    }

    function _assertSelectorSpecificParticipants(bytes4 selector, bytes memory input) internal view {
        if (selector == ICapAccessControlLike.grantAccess.selector) {
            _assertNotListed(_addressArg(input, 2));
            return;
        }
        if (selector == ICapAccessControlLike.revokeAccess.selector) {
            _assertNotListed(_addressArg(input, 2));
            return;
        }
        if (selector == ICapERC20Like.transfer.selector) {
            _assertNotListed(_addressArg(input, 0));
            return;
        }
        if (selector == ICapERC20Like.transferFrom.selector) {
            _assertNotListed(_addressArg(input, 0));
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        if (selector == ICapERC20Like.approve.selector) {
            _assertNotListed(_addressArg(input, 0));
            return;
        }
        if (selector == ICapERC20Like.permit.selector) {
            _assertNotListed(_addressArg(input, 0));
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        if (selector == ICapERC4626Like.deposit.selector || selector == ICapERC4626Like.mint.selector) {
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        if (selector == ICapERC4626Like.withdraw.selector || selector == ICapERC4626Like.redeem.selector) {
            _assertNotListed(_addressArg(input, 1));
            _assertNotListed(_addressArg(input, 2));
            return;
        }
        _assertCapSpecificParticipants(selector, input);
    }

    function _assertCapSpecificParticipants(bytes4 selector, bytes memory input) internal view {
        if (selector == ICapLenderLike.borrow.selector || selector == ICapVaultLike.borrow.selector) {
            _assertNotListed(_addressArg(input, 2));
            return;
        }
        if (selector == ICapLenderLike.repay.selector) {
            _assertNotListed(_addressArg(input, 2));
            return;
        }
        if (
            selector == ICapLenderLike.realizeRestakerInterest.selector
                || selector == ICapLenderLike.openLiquidation.selector
                || selector == ICapLenderLike.closeLiquidation.selector || selector == ICapLenderLike.liquidate.selector
        ) {
            _assertNotListed(_addressArg(input, 0));
            return;
        }
        if (selector == ICapLenderLike.setInterestReceiver.selector) {
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        if (selector == ICapStabledropLike.approveOperator.selector) {
            _assertNotListed(_addressArg(input, 0));
            return;
        }
        if (selector == ICapStabledropLike.approveOperatorFor.selector) {
            _assertNotListed(_addressArg(input, 0));
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        if (selector == ICapStabledropLike.claim.selector) {
            _assertNotListed(_addressArg(input, 0));
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        if (selector == ICapStabledropLike.recoverERC20.selector) {
            _assertNotListed(_addressArg(input, 1));
            return;
        }
        _assertVaultParticipants(selector, input);
    }

    function _assertVaultParticipants(bytes4 selector, bytes memory input) internal view {
        if (selector == ICapVaultLike.mint.selector || selector == ICapVaultLike.burn.selector) {
            _assertNotListed(_addressArg(input, 3));
            return;
        }
        if (selector == ICapVaultLike.redeem.selector) {
            _assertNotListed(_addressArg(input, 2));
            return;
        }
        if (selector == ICapVaultLike.setInsuranceFund.selector) {
            _assertNotListed(_addressArg(input, 0));
            return;
        }
        if (selector == ICapVaultLike.rescueERC20.selector) {
            _assertNotListed(_addressArg(input, 1));
        }
    }

    function _triggeredCaller(PhEvm.TriggerContext memory ctx) internal view returns (address caller) {
        PhEvm.TriggerCall[] memory calls =
            ph.matchingCalls(ph.getAssertionAdopter(), ctx.selector, _successOnlyFilter(), MAX_MATCHING_CALLS);

        for (uint256 i = 0; i < calls.length; i++) {
            if (calls[i].callId == ctx.callStart) return calls[i].caller;
        }

        revert("CapOFAC: triggering call not found");
    }

    function _assertNotListed(address account) internal view {
        if (account == address(0)) return;
        require(!OFAC.isListed(account), "CapOFAC: listed address");
    }

    function _addressArg(bytes memory input, uint256 argIndex) internal pure returns (address account) {
        uint256 offset = 4 + (argIndex * 32);
        require(input.length >= offset + 32, "CapOFAC: malformed calldata");

        assembly {
            account := shr(96, mload(add(add(input, 0x20), offset)))
        }
    }
}
