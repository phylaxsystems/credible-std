// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Assertion} from "../../../../Assertion.sol";
import {PhEvm} from "../../../../PhEvm.sol";
import {console} from "../../../../Console.sol";
import {MockERC20} from "../../src/MockERC20.sol";

/// @title ERC20Assertion
/// @notice Contract containing invariant assertions for ERC20 token transfers
/// @dev These assertions verify that transfers maintain proper balance accounting
contract ERC20Assertion is Assertion {
    /// @notice Registers which functions should trigger which assertions
    /// @dev Links transfer and transferFrom functions to their respective invariant checks
    function triggers() external view override {
        registerCallTrigger(this.assertionTransferInvariant.selector, MockERC20.transfer.selector);
        registerCallTrigger(this.assertionTransferFromInvariant.selector, MockERC20.transferFrom.selector);
    }

    /// @notice Verifies the transfer invariant
    /// @dev This assertion ensures that:
    /// 1. Sender's balance decreases by exactly the transfer amount
    /// 2. Receiver's balance increases by exactly the transfer amount
    /// 3. Total supply remains unchanged
    /// 4. No tokens are created or destroyed during transfer
    function assertionTransferInvariant() external {
        MockERC20 token = MockERC20(ph.getAssertionAdopter());

        // Get all transfer calls that occurred
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(token), MockERC20.transfer.selector);

        // Capture the state before any transfers
        ph.forkPreTx();
        uint256 preTotalSupply = token.totalSupply();

        // Capture the state after transfers
        ph.forkPostTx();
        uint256 postTotalSupply = token.totalSupply();

        // Ensure total supply never changes during transfers
        require(postTotalSupply == preTotalSupply, "Total supply changed during transfer");

        // Check each transfer call individually
        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the transfer parameters
            (address to, uint256 amount) = abi.decode(calls[i].input, (address, uint256));
            address from = calls[i].caller;

            // Get balances before the transfer
            ph.forkPreCall(calls[i].id);
            uint256 fromPreBalance = token.balanceOf(from);
            uint256 toPreBalance = token.balanceOf(to);

            // Get balances after the transfer
            ph.forkPostCall(calls[i].id);
            uint256 fromPostBalance = token.balanceOf(from);
            uint256 toPostBalance = token.balanceOf(to);

            // Handle self-transfer case (from == to)
            if (from == to) {
                require(fromPostBalance == fromPreBalance, "Self-transfer changed balance");
            } else {
                // Verify sender's balance decreased by the correct amount
                // TODO: This is broken on purpose for testing purposes, change it back to - amount
                require(fromPostBalance == fromPreBalance + amount, "Sender balance not decreased correctly");

                // Verify receiver's balance increased by the correct amount
                require(toPostBalance == toPreBalance + amount, "Receiver balance not increased correctly");
            }
        }
    }

    /// @notice Verifies the transferFrom invariant
    /// @dev This assertion ensures that:
    /// 1. Sender's balance decreases by exactly the transfer amount
    /// 2. Receiver's balance increases by exactly the transfer amount
    /// 3. Total supply remains unchanged
    /// 4. No tokens are created or destroyed during transferFrom
    function assertionTransferFromInvariant() external {
        MockERC20 token = MockERC20(ph.getAssertionAdopter());

        // Get all transferFrom calls that occurred
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(token), MockERC20.transferFrom.selector);

        // Capture the state before any transfers
        ph.forkPreTx();
        uint256 preTotalSupply = token.totalSupply();

        // Capture the state after transfers
        ph.forkPostTx();
        uint256 postTotalSupply = token.totalSupply();

        // Ensure total supply never changes during transfers
        require(postTotalSupply == preTotalSupply, "Total supply changed during transferFrom");

        // Check each transferFrom call individually
        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the transferFrom parameters
            (address from, address to, uint256 amount) = abi.decode(calls[i].input, (address, address, uint256));

            // Get balances before the transfer
            ph.forkPreCall(calls[i].id);
            uint256 fromPreBalance = token.balanceOf(from);
            uint256 toPreBalance = token.balanceOf(to);

            // Get balances after the transfer
            ph.forkPostCall(calls[i].id);
            uint256 fromPostBalance = token.balanceOf(from);
            uint256 toPostBalance = token.balanceOf(to);

            // Handle self-transfer case (from == to)
            if (from == to) {
                require(fromPostBalance == fromPreBalance, "Self-transferFrom changed balance");
            } else {
                // Verify sender's balance decreased by the correct amount
                require(
                    fromPostBalance == fromPreBalance - amount, "Sender balance not decreased correctly in transferFrom"
                );

                // Verify receiver's balance increased by the correct amount
                require(
                    toPostBalance == toPreBalance + amount, "Receiver balance not increased correctly in transferFrom"
                );
            }
        }
    }
}
