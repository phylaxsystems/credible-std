// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PhEvm} from "credible-std/PhEvm.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";

import {MellowCuratorHelpers} from "./MellowCuratorHelpers.sol";
import {IMellowVaultConfig} from "./MellowCuratorInterfaces.sol";

/// @title MellowConfigLockAssertion
/// @author Phylax Systems
/// @notice Freezes a Mellow vault's trust graph and proxy implementation within a single
///         user-facing transaction.
/// @dev Apply to the `Vault` (a `TransparentUpgradeableProxy`).
///
///      Two integrity properties the curator should never be able to rewrite unilaterally inside an
///      ordinary transaction:
///      - **Trust graph**: the vault's wired `oracle`, `shareManager`, `feeManager`, and
///        `riskManager`. In flexible-vaults these are set once at initialization and have no
///        on-chain setter, so the only way to change one is a proxy upgrade or a storage collision.
///        Swapping the oracle (price source) or share manager (mint/burn authority) for an
///        attacker-controlled contract is the single highest-impact config attack. Checked by value
///        at transaction end, so the property holds regardless of *how* a change was attempted.
///      - **Proxy implementation/admin**: the EIP-1967 implementation and admin slots. A rogue
///        upgrade swaps the entire vault logic in one call.
///
///      Each trust-graph field is opt-in: pass the expected address to lock it, or `address(0)` to
///      leave it unchecked. The proxy-slot lock is always active.
///
///      False-trip: a *legitimate* governance upgrade is exactly what trips this. That is intended —
///      the property is "config does not change inside a normal user transaction." A planned upgrade
///      should run with the assertion disarmed, or behind a separate timelock-gated path that the
///      adoption deliberately excludes. Document the upgrade runbook alongside the adoption.
///
///      Trigger note: this example uses transaction-end triggers so both checks are exercised by
///      local `pcl test`. In production the proxy-slot lock is cheaper as a
///      `registerStorageChangeTrigger` on the two EIP-1967 slots, firing only when a slot is
///      actually written.
contract MellowConfigLockAssertion is MellowCuratorHelpers {
    /// @notice EIP-1967 implementation slot: `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice EIP-1967 admin slot: `keccak256("eip1967.proxy.admin") - 1`.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice Vault proxy whose config is locked (the assertion adopter).
    address public immutable vault;

    /// @notice Expected wired addresses; `address(0)` leaves that field unchecked.
    address public immutable expectedOracle;
    address public immutable expectedShareManager;
    address public immutable expectedFeeManager;
    address public immutable expectedRiskManager;

    constructor(
        address vault_,
        address expectedOracle_,
        address expectedShareManager_,
        address expectedFeeManager_,
        address expectedRiskManager_
    ) {
        require(vault_ != address(0), "MellowConfig: zero vault");

        vault = vault_;
        expectedOracle = expectedOracle_;
        expectedShareManager = expectedShareManager_;
        expectedFeeManager = expectedFeeManager_;
        expectedRiskManager = expectedRiskManager_;

        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    /// @notice Wires both config-integrity checks at transaction end.
    function triggers() external view override {
        registerTxEndTrigger(this.assertTrustGraphIntact.selector);
        registerTxEndTrigger(this.assertProxyImplementationLocked.selector);
    }

    /// @notice Requires the vault's wired modules to match the expected addresses after the tx.
    /// @dev Read by value at the post-transaction snapshot. Each field is checked only when an
    ///      expected address was configured. A failure means a transaction left the vault pointing
    ///      at a different oracle/share manager/fee manager/risk manager than adoption approved —
    ///      e.g. an upgrade or storage collision rewired the trust graph.
    function assertTrustGraphIntact() external view {
        PhEvm.ForkId memory post = _postTx();

        if (expectedOracle != address(0)) {
            require(
                _readAddressAt(vault, abi.encodeCall(IMellowVaultConfig.oracle, ()), post) == expectedOracle,
                "MellowConfig: oracle rewired"
            );
        }
        if (expectedShareManager != address(0)) {
            require(
                _readAddressAt(vault, abi.encodeCall(IMellowVaultConfig.shareManager, ()), post)
                    == expectedShareManager,
                "MellowConfig: share manager rewired"
            );
        }
        if (expectedFeeManager != address(0)) {
            require(
                _readAddressAt(vault, abi.encodeCall(IMellowVaultConfig.feeManager, ()), post) == expectedFeeManager,
                "MellowConfig: fee manager rewired"
            );
        }
        if (expectedRiskManager != address(0)) {
            require(
                _readAddressAt(vault, abi.encodeCall(IMellowVaultConfig.riskManager, ()), post) == expectedRiskManager,
                "MellowConfig: risk manager rewired"
            );
        }
    }

    /// @notice Requires the EIP-1967 implementation and admin slots to be unwritten during the tx.
    /// @dev `forbidChangeForSlots` flags any SSTORE to a protected slot (even a same-value write),
    ///      with writes inside reverted internal calls rolled back. A failure means the vault proxy
    ///      was upgraded or re-admined inside the transaction.
    function assertProxyImplementationLocked() external view {
        bytes32[] memory slots = new bytes32[](2);
        slots[0] = IMPLEMENTATION_SLOT;
        slots[1] = ADMIN_SLOT;
        require(ph.forbidChangeForSlots(slots), "MellowConfig: proxy implementation or admin changed");
    }
}
