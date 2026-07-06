// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Assertion} from "../../../src/Assertion.sol";
import {PhEvm} from "../../../src/PhEvm.sol";
import {AssertionSpec} from "../../../src/SpecRecorder.sol";
import {IERC4626} from "../../../src/protection/vault/IERC4626.sol";
import {ERC4626BaseAssertion} from "../../../src/protection/vault/ERC4626BaseAssertion.sol";
import {ERC4626SharePriceAssertion} from "../../../src/protection/vault/ERC4626SharePriceAssertion.sol";

// Re-export the SHIPPED MetaMorpho bundle so the test can arm it by type on this vault.
// It bundles ERC4626SharePriceAssertion + ERC4626PreviewAssertion + ERC4626CumulativeOutflowAssertion —
// the library's recommended set for "computed-asset" vaults where balance != totalAssets(),
// which is exactly the FleetCommander/Ark shape.
import {MetaMorphoVaultAssertion} from "../../../src/protection/vault/examples/MetaMorphoVaultAssertion.sol";

/// @notice Shipped `ERC4626SharePriceAssertion` logic, wired with ONLY the transaction-end
///         envelope trigger. Reuses the inherited `assertSharePriceEnvelope()` verbatim
///         (which calls `ph.assetsMatchSharePrice` over all fork points).
contract SummerSharePriceTxEnd is ERC4626SharePriceAssertion {
    constructor(address vault_, address asset_, uint256 toleranceBps_)
        ERC4626BaseAssertion(vault_, asset_)
        ERC4626SharePriceAssertion(toleranceBps_)
    {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertSharePriceEnvelope.selector);
    }
}

/// @notice Treats `FleetCommander.convertToAssets(probe)` as a price oracle and checks it for
///         intra-transaction deviation across ALL fork points, firing at transaction end.
///
/// @dev This is the same idea as the vault_demo `VaultConvertToAssetsOracleSanityAssertion`, but
///      with a `registerTxEndTrigger` instead of a `registerFnCallTrigger(..., donateAssets)`.
///      The distinction is the whole point of this reproduction: the Summer donation is a plain
///      `vgUSDC.transfer(ark, x)` — it never calls the vault, so an fnCall trigger on the vault
///      would never fire. Only a tx-end (or storage/balance-change) trigger observes it.
contract SummerConvertToAssetsGuardTxEnd is Assertion {
    address internal immutable vault;
    uint256 internal immutable probeShares;
    uint256 internal immutable maxDeviationBps;

    constructor(address vault_, uint256 probeShares_, uint256 maxDeviationBps_) {
        vault = vault_;
        probeShares = probeShares_;
        maxDeviationBps = maxDeviationBps_;
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    function triggers() external view override {
        registerTxEndTrigger(this.assertConvertToAssetsSanity.selector);
    }

    function assertConvertToAssetsSanity() external {
        require(
            ph.oracleSanity(vault, abi.encodeCall(IERC4626.convertToAssets, (probeShares)), maxDeviationBps),
            "Summer: convertToAssets deviated"
        );
    }
}
