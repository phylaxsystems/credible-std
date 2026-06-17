// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {LidoStEthVaultPegAssertion} from "../src/LidoStEthVaultPegAssertion.sol";
import {MockChainlinkFeed, MockWstETH, MockRateSource, MockShareToken} from "./LidoMocks.sol";

contract LidoStEthVaultPegAssertionTest is Test, CredibleTest {
    MockShareToken internal shareToken;
    MockChainlinkFeed internal feed;
    MockWstETH internal wstEth;
    MockRateSource internal provider;

    address internal alice = makeAddr("alice");

    uint256 internal constant MAX_DEPEG_BPS = 100; // 1%
    uint256 internal constant MAX_MISMATCH_BPS = 50; // 0.5%

    function setUp() public {
        shareToken = new MockShareToken();
        feed = new MockChainlinkFeed(1e18, block.timestamp); // on peg, fresh
        wstEth = new MockWstETH();
        provider = new MockRateSource(1e18);

        shareToken.mint(alice, 100 ether); // starting supply to mint/burn against
    }

    function _arm(bytes4 sel, uint256 maxFeedStalenessSecs) internal {
        bytes memory createData = abi.encodePacked(
            type(LidoStEthVaultPegAssertion).creationCode,
            abi.encode(
                address(shareToken),
                address(feed),
                uint8(18),
                MAX_DEPEG_BPS,
                maxFeedStalenessSecs,
                address(wstEth),
                address(provider),
                MAX_MISMATCH_BPS
            )
        );
        cl.assertion(address(shareToken), createData, sel);
    }

    // --- Supply-change depeg gate ------------------------------------------

    function testMintOnPegPasses() public {
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);
        shareToken.mint(alice, 10 ether);
    }

    function testBurnOnPegPasses() public {
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);
        shareToken.burn(alice, 10 ether);
    }

    function testMintWhileDepeggedTrips() public {
        feed.setAnswer(0.95e18); // 5% off peg
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);

        vm.expectRevert(bytes("LidoVault: stETH off peg, share pricing unsafe"));
        shareToken.mint(alice, 10 ether);
    }

    function testBurnWhileDepeggedTrips() public {
        feed.setAnswer(1.05e18); // 5% off peg the other way
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);

        vm.expectRevert(bytes("LidoVault: stETH off peg, share pricing unsafe"));
        shareToken.burn(alice, 10 ether);
    }

    function testNoSupplyChangePassesEvenWhenDepegged() public {
        feed.setAnswer(0.95e18); // depegged, but this tx does not move supply
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);

        // Touches the share token (poking an unrelated rate) without minting/burning.
        shareToken.setProviderRate(provider, 1e18);
    }

    // --- Feed staleness / round integrity (fail closed) --------------------

    function testMintWhileFeedStaleTrips() public {
        // Answer is on peg, but the round is older than the 1h max age.
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 1 hours);
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(bytes("LidoVault: stETH off peg, share pricing unsafe"));
        shareToken.mint(alice, 10 ether);
    }

    function testMintWhileRoundIncompleteTrips() public {
        feed.setRound(2, 1e18, 0, 2); // updatedAt == 0: incomplete round
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);

        vm.expectRevert(bytes("LidoVault: stETH off peg, share pricing unsafe"));
        shareToken.mint(alice, 10 ether);
    }

    function testMintWhileRoundStaleTrips() public {
        feed.setRound(5, 1e18, block.timestamp, 4); // answeredInRound < roundId: carried-over answer
        _arm(LidoStEthVaultPegAssertion.assertMintBurnPegSafety.selector, 0);

        vm.expectRevert(bytes("LidoVault: stETH off peg, share pricing unsafe"));
        shareToken.mint(alice, 10 ether);
    }

    // --- wstETH rate integrity ---------------------------------------------

    function testRateIntegrityPasses() public {
        _arm(LidoStEthVaultPegAssertion.assertWstEthRateIntegrity.selector, 0);
        // Provider matches the protocol rate exactly.
        shareToken.setProviderRate(provider, 1e18);
    }

    function testWstEthRateDecreaseTrips() public {
        wstEth.setRate(1.1e18); // pre-tx protocol rate
        _arm(LidoStEthVaultPegAssertion.assertWstEthRateIntegrity.selector, 0);

        vm.expectRevert(bytes("LidoVault: wstETH rate decreased in transaction"));
        shareToken.setWstEthRate(wstEth, 1.0e18); // a decrease cannot happen mid-tx
    }

    function testProviderDesyncTrips() public {
        _arm(LidoStEthVaultPegAssertion.assertWstEthRateIntegrity.selector, 0);

        // Provider reports 1.1 against a protocol rate of 1.0: 10% off, past the 0.5% tolerance.
        vm.expectRevert(bytes("LidoVault: rate provider desynced from Lido rate"));
        shareToken.setProviderRate(provider, 1.1e18);
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroShareToken() public {
        vm.expectRevert(bytes("LidoVault: zero share token"));
        new LidoStEthVaultPegAssertion(
            address(0), address(feed), 18, MAX_DEPEG_BPS, 0, address(wstEth), address(provider), MAX_MISMATCH_BPS
        );
    }

    function testRejectsZeroWstEth() public {
        vm.expectRevert(bytes("LidoVault: zero wstETH"));
        new LidoStEthVaultPegAssertion(
            address(shareToken), address(feed), 18, MAX_DEPEG_BPS, 0, address(0), address(provider), MAX_MISMATCH_BPS
        );
    }

    function testDeploys() public {
        LidoStEthVaultPegAssertion assertion = new LidoStEthVaultPegAssertion(
            address(shareToken),
            address(feed),
            18,
            MAX_DEPEG_BPS,
            1 hours,
            address(wstEth),
            address(provider),
            MAX_MISMATCH_BPS
        );
        assertTrue(address(assertion) != address(0));
    }
}
