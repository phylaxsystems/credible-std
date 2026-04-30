// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ERC4626Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC4626Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {ERC4626SharePriceAssertion} from "../../../src/protection/vault/ERC4626SharePriceAssertion.sol";
import {ERC4626PreviewAssertion} from "../../../src/protection/vault/ERC4626PreviewAssertion.sol";
import {GenericErc4626Bundle} from "../../fixtures/vault/GenericErc4626Bundle.sol";
import {MaliciousErc4626} from "../../fixtures/vault/MaliciousErc4626.sol";

/// @title Erc4626AssertionTest
/// @notice cl.assertion-armed regression tests for the credible-std ERC-4626 assertion bundle.
/// @dev `cl.assertion` arms a single assertion function per call, consumed by the next monitored
///      external call. Each test below arms one specific check (share price, preview, etc.) before
///      issuing the matching vault operation. Honest paths use the OpenZeppelin reference vault;
///      malicious paths use `MaliciousErc4626` to break exactly one invariant per scenario.
contract Erc4626AssertionTest is Test, CredibleTest {
    uint256 internal constant SHARE_PRICE_TOLERANCE_BPS = 50;
    uint256 internal constant OUTFLOW_THRESHOLD_BPS = 5_000;
    uint256 internal constant OUTFLOW_WINDOW = 24 hours;

    ERC20Mock internal asset;
    ERC4626Mock internal honestVault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        asset = new ERC20Mock();
        honestVault = new ERC4626Mock(address(asset));

        asset.mint(alice, 1_000_000 ether);
        asset.mint(bob, 1_000_000 ether);
        vm.prank(alice);
        asset.approve(address(honestVault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(honestVault), type(uint256).max);

        // Establish non-trivial pre-state so share-price math has both sides positive.
        vm.prank(alice);
        honestVault.deposit(100_000 ether, alice);
    }

    function _armOnHonest(bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(GenericErc4626Bundle).creationCode,
            abi.encode(
                address(honestVault),
                address(asset),
                SHARE_PRICE_TOLERANCE_BPS,
                OUTFLOW_THRESHOLD_BPS,
                OUTFLOW_WINDOW
            )
        );
        cl.assertion(address(honestVault), createData, fnSelector);
    }

    function _armOnMalicious(address vault, bytes4 fnSelector) internal {
        bytes memory createData = abi.encodePacked(
            type(GenericErc4626Bundle).creationCode,
            abi.encode(vault, address(asset), SHARE_PRICE_TOLERANCE_BPS, OUTFLOW_THRESHOLD_BPS, OUTFLOW_WINDOW)
        );
        cl.assertion(vault, createData, fnSelector);
    }

    function _seedMalicious(MaliciousErc4626 vault, address user, uint256 mintAmount, uint256 initialDeposit)
        internal
    {
        asset.mint(user, mintAmount);
        vm.prank(user);
        asset.approve(address(vault), type(uint256).max);
        if (initialDeposit > 0) {
            vm.prank(user);
            vault.deposit(initialDeposit, user);
        }
    }

    // -----------------------------------------------------------------
    //  Honest paths — armed per-call assertions must pass on a correct vault
    // -----------------------------------------------------------------

    /// @notice Honest deposit must satisfy the per-call share-price check.
    function testHonestDepositSharePricePasses() public {
        _armOnHonest(ERC4626SharePriceAssertion.assertPerCallSharePrice.selector);
        vm.prank(bob);
        honestVault.deposit(50_000 ether, bob);
    }

    /// @notice Honest deposit's actual shares minted matches `previewDeposit` exactly.
    function testHonestDepositPreviewPasses() public {
        _armOnHonest(ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.prank(bob);
        honestVault.deposit(50_000 ether, bob);
    }

    /// @notice Honest mint's actual assets charged matches `previewMint` exactly.
    function testHonestMintPreviewPasses() public {
        _armOnHonest(ERC4626PreviewAssertion.assertMintPreview.selector);
        vm.prank(bob);
        honestVault.mint(50_000 ether, bob);
    }

    /// @notice Honest withdraw's actual shares burned matches `previewWithdraw` exactly.
    function testHonestWithdrawPreviewPasses() public {
        _armOnHonest(ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vm.prank(alice);
        honestVault.withdraw(10_000 ether, alice, alice);
    }

    /// @notice Honest redeem's actual assets returned matches `previewRedeem` exactly.
    function testHonestRedeemPreviewPasses() public {
        _armOnHonest(ERC4626PreviewAssertion.assertRedeemPreview.selector);
        vm.prank(alice);
        honestVault.redeem(10_000 ether, alice, alice);
    }

    // -----------------------------------------------------------------
    //  Bundle deployment / smoke
    // -----------------------------------------------------------------

    /// @notice Bundle deploys via plain `new` and resolves all multi-inheritance correctly.
    function testBundleDeploysStandalone() public {
        GenericErc4626Bundle bundle = new GenericErc4626Bundle(
            address(honestVault), address(asset), SHARE_PRICE_TOLERANCE_BPS, OUTFLOW_THRESHOLD_BPS, OUTFLOW_WINDOW
        );
        assertTrue(address(bundle) != address(0));
    }

    // -----------------------------------------------------------------
    //  Malicious paths — armed assertion must trip on the matching violation
    // -----------------------------------------------------------------

    /// @notice A vault that mints far more shares than `previewDeposit` returned must trip the
    ///         deposit-preview deviation check (`actualShares - previewShares > maxDeviation`).
    function testInflatedDepositSharesTripsPreview() public {
        MaliciousErc4626 vault = new MaliciousErc4626(address(asset), MaliciousErc4626.Mode.InflatedDepositShares);
        _seedMalicious(vault, alice, 10_000 ether, 1_000 ether);

        _armOnMalicious(address(vault), ERC4626PreviewAssertion.assertDepositPreview.selector);
        vm.prank(alice);
        vm.expectRevert(bytes("ERC4626: deposit preview deviates from actual"));
        vault.deposit(1_000 ether, alice);
    }

    /// @notice A vault that pulls assets but mints zero shares destroys per-share value for
    ///         incumbents. Trips the per-call share-price check.
    function testSharePriceDropTripsPerCallCheck() public {
        MaliciousErc4626 vault = new MaliciousErc4626(address(asset), MaliciousErc4626.Mode.SharePriceDrop);
        _seedMalicious(vault, alice, 10_000 ether, 1_000 ether);
        _seedMalicious(vault, bob, 10_000 ether, 0);

        _armOnMalicious(address(vault), ERC4626SharePriceAssertion.assertPerCallSharePrice.selector);
        vm.prank(bob);
        vm.expectRevert(bytes("ERC4626: call-level share price drift exceeds tolerance"));
        vault.deposit(1_000 ether, bob);
    }

    /// @notice A vault that burns fewer shares than `previewWithdraw` returned must trip the
    ///         withdraw-preview deviation check.
    function testDepressedWithdrawSharesTripsPreview() public {
        MaliciousErc4626 vault = new MaliciousErc4626(address(asset), MaliciousErc4626.Mode.DepressedWithdrawShares);
        _seedMalicious(vault, alice, 10_000 ether, 2_000 ether);

        _armOnMalicious(address(vault), ERC4626PreviewAssertion.assertWithdrawPreview.selector);
        vm.prank(alice);
        vm.expectRevert(bytes("ERC4626: withdraw preview deviates from actual"));
        vault.withdraw(1_000 ether, alice, alice);
    }
}
