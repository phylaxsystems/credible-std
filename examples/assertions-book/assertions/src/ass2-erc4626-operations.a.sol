// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title ERC4626OperationsAssertion
 * @notice This assertion contract validates the correctness of ERC4626 vault operations by checking:
 *
 * 1. Batch Operations Consistency:
 *    - Validates that all ERC4626 operations (deposit, mint, withdraw, redeem) maintain correct
 *      accounting of total assets and total supply
 *    - Ensures that the net changes in assets and shares match the expected changes
 *    - Handles multiple operations in a single transaction
 *
 * 2. Deposit Operation Validation:
 *    - Verifies that deposit operations correctly increase the vault's asset balance
 *    - Ensures depositors receive the correct number of shares based on previewDeposit
 *    - Validates that the vault's total assets increase by exactly the deposited amount
 *
 * 3. Base Invariants:
 *    - Ensures the vault always has at least as many assets as shares
 *    - Validates this invariant after any storage changes
 *
 * The contract uses the Credible Layer's fork mechanism to compare pre and post-state
 * changes, ensuring that all operations maintain the vault's accounting integrity.
 */
import {Assertion} from "credible-std/Assertion.sol";
import {AssertionSpec} from "credible-std/SpecRecorder.sol";
import {CoolVault} from "../../src/ass2-erc4626-operations.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract ERC4626OperationsAssertion is Assertion {
    constructor() {
        registerAssertionSpec(AssertionSpec.Reshiram);
    }

    // The triggers function tells the Credible Layer which assertion functions to run
    function triggers() external view override {
        // Batch operations assertion - triggers on any of the four functions
        registerFnCallTrigger(this.assertionBatchOperationsConsistency.selector, CoolVault.deposit.selector);
        registerFnCallTrigger(this.assertionBatchOperationsConsistency.selector, CoolVault.mint.selector);
        registerFnCallTrigger(this.assertionBatchOperationsConsistency.selector, CoolVault.withdraw.selector);
        registerFnCallTrigger(this.assertionBatchOperationsConsistency.selector, CoolVault.redeem.selector);

        // Deposit-specific assertions
        registerFnCallTrigger(this.assertionDepositIncreasesBalance.selector, CoolVault.deposit.selector);
        registerFnCallTrigger(this.assertionDepositerSharesIncreases.selector, CoolVault.deposit.selector);

        // Base invariant assertion - triggers on storage changes
        registerTxEndTrigger(this.assertionVaultAlwaysAccumulatesAssets.selector);
    }

    /**
     * @dev Comprehensive assertion for batch operations: validates that all ERC4626 operations
     * in a single transaction maintain consistency across total supply and total assets
     * This function checks all four operations (deposit, mint, withdraw, redeem) that may occur
     * within the same transaction and ensures the final state is mathematically correct
     */
    function assertionBatchOperationsConsistency() external {
        // Get the assertion adopter address
        CoolVault adopter = CoolVault(ph.getAssertionAdopter());

        // Get call inputs for all four functions
        PhEvm.CallInputs[] memory depositInputs = ph.getCallInputs(address(adopter), adopter.deposit.selector);
        PhEvm.CallInputs[] memory mintInputs = ph.getCallInputs(address(adopter), adopter.mint.selector);
        PhEvm.CallInputs[] memory withdrawInputs = ph.getCallInputs(address(adopter), adopter.withdraw.selector);
        PhEvm.CallInputs[] memory redeemInputs = ph.getCallInputs(address(adopter), adopter.redeem.selector);

        // Calculate net changes from all operations
        uint256 totalAssetsAdded = 0;
        uint256 totalAssetsRemoved = 0;
        uint256 totalSharesAdded = 0;
        uint256 totalSharesRemoved = 0;

        // Process deposit operations (increase assets and supply)
        for (uint256 i = 0; i < depositInputs.length; i++) {
            (uint256 assets,) = abi.decode(depositInputs[i].input, (uint256, address));
            totalAssetsAdded += assets;
            totalSharesAdded += adopter.previewDeposit(assets);
        }

        // Process mint operations (increase assets and supply)
        for (uint256 i = 0; i < mintInputs.length; i++) {
            (uint256 shares,) = abi.decode(mintInputs[i].input, (uint256, address));
            totalSharesAdded += shares;
            totalAssetsAdded += adopter.previewMint(shares);
        }

        // Process withdraw operations (decrease assets and supply)
        for (uint256 i = 0; i < withdrawInputs.length; i++) {
            (uint256 assets,,) = abi.decode(withdrawInputs[i].input, (uint256, address, address));
            totalAssetsRemoved += assets;
            totalSharesRemoved += adopter.previewWithdraw(assets);
        }

        // Process redeem operations (decrease assets and supply)
        for (uint256 i = 0; i < redeemInputs.length; i++) {
            (uint256 shares,,) = abi.decode(redeemInputs[i].input, (uint256, address, address));
            totalSharesRemoved += shares;
            totalAssetsRemoved += adopter.previewRedeem(shares);
        }

        PhEvm.ForkId memory preFork = _preTx();
        uint256 preVaultAssets = adopter.totalAssets();
        uint256 preVaultSupply = adopter.totalSupply();

        PhEvm.ForkId memory postFork = _postTx();
        uint256 postVaultAssets = adopter.totalAssets();
        uint256 postVaultSupply = adopter.totalSupply();

        // Calculate expected changes
        uint256 expectedAssetsAdded = postVaultAssets > preVaultAssets ? postVaultAssets - preVaultAssets : 0;
        uint256 expectedAssetsRemoved = preVaultAssets > postVaultAssets ? preVaultAssets - postVaultAssets : 0;
        uint256 expectedSharesAdded = postVaultSupply > preVaultSupply ? postVaultSupply - preVaultSupply : 0;
        uint256 expectedSharesRemoved = preVaultSupply > postVaultSupply ? preVaultSupply - postVaultSupply : 0;

        // Ensure operations had some effect if there were calls
        require(totalAssetsAdded == expectedAssetsAdded, "Batch Operations: Assets added mismatch");
        require(totalAssetsRemoved == expectedAssetsRemoved, "Batch Operations: Assets removed mismatch");
        require(totalSharesAdded == expectedSharesAdded, "Batch Operations: Shares added mismatch");
        require(totalSharesRemoved == expectedSharesRemoved, "Batch Operations: Shares removed mismatch");
    }

    /**
     * @dev Assertion to verify that deposit operations correctly increase the vault's asset balance
     * This ensures that when users deposit assets, the vault's total assets increase by exactly the deposited amount
     */
    function assertionDepositIncreasesBalance() external {
        // Get the assertion adopter address
        CoolVault adopter = CoolVault(ph.getAssertionAdopter());

        // Get all deposit calls to the vault
        PhEvm.CallInputs[] memory inputs = ph.getCallInputs(address(adopter), adopter.deposit.selector);

        for (uint256 i = 0; i < inputs.length; i++) {
            (uint256 assets, address receiver) = abi.decode(inputs[i].input, (uint256, address));

            // Check pre-state
            PhEvm.ForkId memory preFork = _preTx();
            uint256 vaultAssetPreBalance = adopter.totalAssets();
            uint256 userSharesPreBalance = adopter.balanceOf(receiver);
            uint256 expectedShares = adopter.previewDeposit(assets);

            // Check post-state
            PhEvm.ForkId memory postFork = _postTx();
            uint256 vaultAssetPostBalance = adopter.totalAssets();
            uint256 userSharesPostBalance = adopter.balanceOf(receiver);

            // Verify vault assets increased by exactly the deposited amount
            require(
                vaultAssetPostBalance == vaultAssetPreBalance + assets,
                "Deposit assertion failed: Vault assets did not increase by the correct amount"
            );

            // Verify user received exactly the expected number of shares
            require(
                userSharesPostBalance == userSharesPreBalance + expectedShares,
                "Deposit assertion failed: User did not receive the correct number of shares"
            );
        }
    }

    /**
     * @dev Assertion to verify that deposit operations correctly increase the depositor's share balance
     * This ensures that when users deposit assets, they receive the correct number of shares
     */
    function assertionDepositerSharesIncreases() external {
        // Get the assertion adopter address
        CoolVault adopter = CoolVault(ph.getAssertionAdopter());

        PhEvm.CallInputs[] memory inputs = ph.getCallInputs(address(adopter), adopter.deposit.selector);

        for (uint256 i = 0; i < inputs.length; i++) {
            PhEvm.ForkId memory preFork = _preTx();
            (uint256 assets,) = abi.decode(inputs[i].input, (uint256, address));
            uint256 previewPreAssets = adopter.previewDeposit(assets);
            address depositer = inputs[0].caller;
            uint256 preShares = adopter.balanceOf(depositer);

            PhEvm.ForkId memory postFork = _postTx();

            uint256 postShares = adopter.balanceOf(depositer);

            require(
                postShares == preShares + previewPreAssets,
                "Depositer shares assertion failed: Share balance did not increase correctly"
            );
        }
    }

    /**
     * @dev Base invariant assertion to verify that the vault always has at least as many assets as shares
     * This is a fundamental invariant of ERC4626 vaults - they should never have more shares than assets
     */
    function assertionVaultAlwaysAccumulatesAssets() external {
        // Get the assertion adopter address
        CoolVault adopter = CoolVault(ph.getAssertionAdopter());

        PhEvm.ForkId memory postFork = _postTx();

        uint256 vaultAssetPostBalance = adopter.totalAssets();
        uint256 vaultSharesPostBalance = adopter.balanceOf(address(adopter));

        require(
            vaultAssetPostBalance >= vaultSharesPostBalance, "Base invariant failed: Vault has more shares than assets"
        );
    }
}
