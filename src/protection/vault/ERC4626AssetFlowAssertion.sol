// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "../../PhEvm.sol";
import {IERC4626} from "./IERC4626.sol";
import {ERC4626BaseAssertion} from "./ERC4626BaseAssertion.sol";

/// @title ERC4626AssetFlowAssertion
/// @author Phylax Systems
/// @notice Asserts that ERC-20 token movement and the vault's internal asset accounting agree,
///         and that fundamental share-token invariants hold.
///
/// Invariants covered:
///   - **Token movement matches accounting**: the change in totalAssets across the transaction
///     equals the net ERC-20 flow into/out of the vault. This catches transfer-fee tokens,
///     rebasing tokens, or accounting bugs where totalAssets drifts from reality.
///
///   - **Zero address never holds shares**: balanceOf(address(0)) == 0 after every
///     share-minting operation.
///
///
/// @dev Uses V2 `registerTxEndTrigger` for tx-wide checks and
///      `registerFnCallTrigger` + `ph.context()` for call-scoped checks.
abstract contract ERC4626AssetFlowAssertion is ERC4626BaseAssertion {
    /// @notice Register the default trigger set for asset-flow invariants.
    function _registerAssetFlowTriggers() internal view {
        // Tx-wide accounting check — fires once after the transaction completes
        registerTxEndTrigger(this.assertAssetFlowMatchesAccounting.selector);

        // Zero-address share check — fires per deposit/mint call
        registerFnCallTrigger(this.assertZeroAddressHasNoShares.selector, IERC4626.deposit.selector);
        registerFnCallTrigger(this.assertZeroAddressHasNoShares.selector, IERC4626.mint.selector);
    }

    // ---------------------------------------------------------------
    //  Asset flow == accounting
    // ---------------------------------------------------------------

    /// @notice Verifies the change in totalAssets across the tx matches the net ERC-20 flow.
    function assertAssetFlowMatchesAccounting() external {
        uint256 preAssets = _totalAssetsAt(_preTx());
        uint256 postAssets = _totalAssetsAt(_postTx());

        int256 accountingDelta = int256(postAssets) - int256(preAssets);
        int256 netFlow = _netAssetFlow();

        require(accountingDelta == netFlow, "ERC4626: accounting delta != token flow");
    }

    /// @notice Compute net ERC-20 flow into (+) or out of (-) the vault across the tx.
    /// @dev Override for vaults that deploy assets through adapters or external protocols.
    ///      The override should include flows to/from all relevant addresses (vault + adapters).
    function _netAssetFlow() internal view virtual returns (int256 netFlow) {
        PhEvm.Erc20TransferData[] memory deltas = ph.reduceErc20BalanceDeltas(asset, _postTx());

        for (uint256 i = 0; i < deltas.length; i++) {
            if (deltas[i].to == vault) {
                netFlow += int256(deltas[i].value);
            }
            if (deltas[i].from == vault) {
                netFlow -= int256(deltas[i].value);
            }
        }
    }

    // ---------------------------------------------------------------
    //  Share-token invariants
    // ---------------------------------------------------------------

    /// @notice Verifies the zero address never holds vault shares.
    /// @dev Uses ph.context() to check at PostCall of the triggering call.
    function assertZeroAddressHasNoShares() external {
        PhEvm.TriggerContext memory ctx = ph.context();
        require(_shareBalanceAt(address(0), _postCall(ctx.callEnd)) == 0, "ERC4626: zero address holds shares");
    }
}
