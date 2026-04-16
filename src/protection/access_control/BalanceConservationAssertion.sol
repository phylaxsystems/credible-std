// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {AccessControlBaseAssertion} from "./AccessControlBaseAssertion.sol";

/// @title BalanceConservationAssertion
/// @author Phylax Systems
/// @notice Asserts that specified account token balances do not change during the transaction,
///         catching unauthorized balance changes for accounts that should remain untouched.
///
/// Invariants covered:
///   - **Treasury / reserve protection**: treasury or reserve account balances remain unchanged
///     unless an authorized governance path is followed.
///   - **Escrow protection**: escrow contract balances are conserved across the transaction.
///   - **Unauthorized transfer detection**: catches privilege misuse, reentrancy side effects,
///     or unexpected execution paths that drain protected accounts.
///   - **Custodial leg verification**: for RWA protocols, outflows only along known
///     subscription/redemption legs.
///
/// @dev Uses the V2 `conserveBalance(fork0, fork1, token, account)` precompile to compare
///      `balanceOf(account)` at PreTx vs PostTx for each protected (token, account) pair.
///
///      Implementers must override `_conservedBalances()` to declare which (token, account)
///      pairs to protect. For selector-aware outflow caps (e.g., looser limits on approved
///      withdraw/redeem selectors), use per-function triggers and custom assertion logic
///      instead of this mixin.
abstract contract BalanceConservationAssertion is AccessControlBaseAssertion {
    /// @notice A (token, account) pair whose balance must be conserved across the transaction.
    struct ConservedBalance {
        /// @notice The ERC20 token address.
        address token;
        /// @notice The account whose balance should remain unchanged.
        address account;
    }

    /// @notice Returns the (token, account) pairs whose balances must not change.
    /// @dev Override to declare the protocol-specific protected balances. Common targets:
    ///      - Protocol treasury / DAO treasury USDC/ETH balances
    ///      - Pool cash reserves (Maple pool, Centrifuge escrow)
    ///      - Vault reserves and fee-leftover accounts (Lido stVault)
    ///      - Collateral and burner flows (Symbiotic vault)
    ///      - RWAHub / subscription-redemption custodial balances (Ondo)
    /// @return balances Array of (token, account) pairs to conserve.
    function _conservedBalances() internal view virtual returns (ConservedBalance[] memory balances);

    /// @notice Register the default trigger set for balance conservation.
    /// @dev Uses registerTxEndTrigger so the check fires once after the transaction completes.
    ///      Call this inside your `triggers()`.
    function _registerBalanceConservationTriggers() internal view {
        registerTxEndTrigger(this.assertBalanceConservation.selector);
    }

    /// @notice Verifies that all protected account balances are unchanged across the transaction.
    /// @dev Checks each (token, account) pair using the `conserveBalance` precompile at
    ///      PreTx vs PostTx. Reverts on the first pair whose balance changed.
    function assertBalanceConservation() external {
        ConservedBalance[] memory balances = _conservedBalances();
        PhEvm.ForkId memory pre = _preTx();
        PhEvm.ForkId memory post = _postTx();

        for (uint256 i = 0; i < balances.length; i++) {
            require(
                ph.conserveBalance(pre, post, balances[i].token, balances[i].account),
                "AccessControl: protected balance changed"
            );
        }
    }
}
