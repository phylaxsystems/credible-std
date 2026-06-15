// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {LidoStEthExitBufferAssertion} from "../src/LidoStEthExitBufferAssertion.sol";
import {MockERC20, MockWstETH, MockLidoVault} from "./LidoMocks.sol";

contract LidoStEthExitBufferAssertionTest is Test, CredibleTest {
    MockLidoVault internal vault;
    MockERC20 internal stEth;
    MockWstETH internal wstEth;
    MockERC20 internal receipt; // deployed stETH-equivalent receipt (e.g. Aave awstETH)

    address internal sink = makeAddr("sink");

    function setUp() public {
        vault = new MockLidoVault();
        stEth = new MockERC20("Lido stETH", "stETH", 18);
        wstEth = new MockWstETH();
        receipt = new MockERC20("Aave wstETH", "awstETH", 18);
    }

    function _arm(
        bytes4 sel,
        uint256 minIdleStEthEq,
        uint256 minBufferBps,
        uint256 outflowThresholdBps,
        uint256 outflowWindowDuration
    ) internal {
        bytes memory createData = abi.encodePacked(
            type(LidoStEthExitBufferAssertion).creationCode,
            abi.encode(
                address(vault),
                address(stEth),
                address(wstEth),
                address(receipt),
                minIdleStEthEq,
                minBufferBps,
                outflowThresholdBps,
                outflowWindowDuration
            )
        );
        cl.assertion(address(vault), createData, sel);
    }

    // --- Buffer floor ------------------------------------------------------

    function testBufferFloorPassesAboveFloor() public {
        // idle 10 + deployed 90 = 100 total; 5% floor = 5. After moving 1 out, idle 9 >= ~5.
        stEth.setBalance(address(vault), 10 ether);
        receipt.setBalance(address(vault), 90 ether);
        _arm(LidoStEthExitBufferAssertion.assertWithdrawableBufferFloor.selector, 0, 500, 0, 0);

        vault.transferOut(stEth, sink, 1 ether);
    }

    function testBufferFloorTripsBelowRelativeFloor() public {
        // idle 5 + deployed 95 = 100 total; 5% floor = 5. Moving 1 out drops idle to 4 < 5.
        stEth.setBalance(address(vault), 5 ether);
        receipt.setBalance(address(vault), 95 ether);
        _arm(LidoStEthExitBufferAssertion.assertWithdrawableBufferFloor.selector, 0, 500, 0, 0);

        vm.expectRevert(bytes("LidoVault: withdrawable stETH buffer below floor"));
        vault.transferOut(stEth, sink, 1 ether);
    }

    function testBufferFloorTripsBelowAbsoluteFloor() public {
        // Absolute floor of 8 stETH (bps disabled). Total stays > 8, so the floor is not capped.
        stEth.setBalance(address(vault), 10 ether);
        receipt.setBalance(address(vault), 90 ether);
        _arm(LidoStEthExitBufferAssertion.assertWithdrawableBufferFloor.selector, 8 ether, 0, 0, 0);

        vm.expectRevert(bytes("LidoVault: withdrawable stETH buffer below floor"));
        vault.transferOut(stEth, sink, 3 ether); // idle 7 < 8
    }

    function testBufferFloorCountsWstEthAtLidoRate() public {
        // wstETH valued at 1.2 stEthPerToken: idle = 6 wstETH * 1.2 = 7.2 stETH-eq, below the 8 floor.
        wstEth.setRate(1.2e18);
        wstEth.setBalance(address(vault), 6 ether);
        receipt.setBalance(address(vault), 90 ether);
        _arm(LidoStEthExitBufferAssertion.assertWithdrawableBufferFloor.selector, 8 ether, 0, 0, 0);

        // Touch the vault without changing balances; the 7.2 stETH-eq idle is already below floor.
        vm.expectRevert(bytes("LidoVault: withdrawable stETH buffer below floor"));
        vault.transferOut(stEth, sink, 0);
    }

    function testBufferFloorPassesWhenVaultHoldsNothing() public {
        // No stETH at all: nothing to reserve, draining the last of it is the breaker's job.
        _arm(LidoStEthExitBufferAssertion.assertWithdrawableBufferFloor.selector, 1 ether, 500, 0, 0);

        vault.transferOut(stEth, sink, 0);
    }

    // --- Outflow circuit breaker ------------------------------------------

    /// @dev The `watchCumulativeOutflow` trigger that fires `assertOutflowWithinLimit` live is driven
    ///      by the executor's rolling-window accounting and is not simulated by local `pcl test`, so
    ///      the breaker's hard-revert decision is validated by calling it directly rather than via an
    ///      armed `cl.assertion` transaction.
    function testOutflowBreakerRevertsWhenInvoked() public {
        LidoStEthExitBufferAssertion assertion = new LidoStEthExitBufferAssertion(
            address(vault), address(stEth), address(wstEth), address(receipt), 0, 0, 5_000, 1 days
        );
        vm.expectRevert(bytes("LidoVault: stETH outflow circuit breaker tripped"));
        assertion.assertOutflowWithinLimit();
    }

    // --- Constructor wiring ------------------------------------------------

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("LidoVault: zero vault"));
        new LidoStEthExitBufferAssertion(address(0), address(stEth), address(wstEth), address(0), 0, 500, 0, 0);
    }

    function testRejectsZeroStEth() public {
        vm.expectRevert(bytes("LidoVault: zero stETH"));
        new LidoStEthExitBufferAssertion(address(vault), address(0), address(wstEth), address(0), 0, 500, 0, 0);
    }

    function testRejectsZeroWstEth() public {
        vm.expectRevert(bytes("LidoVault: zero wstETH"));
        new LidoStEthExitBufferAssertion(address(vault), address(stEth), address(0), address(0), 0, 500, 0, 0);
    }

    function testRejectsBufferBpsTooLarge() public {
        vm.expectRevert(bytes("LidoVault: buffer bps too large"));
        new LidoStEthExitBufferAssertion(address(vault), address(stEth), address(wstEth), address(0), 0, 10_001, 0, 0);
    }

    function testRejectsOutflowBpsTooLarge() public {
        vm.expectRevert(bytes("LidoVault: outflow bps too large"));
        new LidoStEthExitBufferAssertion(
            address(vault), address(stEth), address(wstEth), address(0), 0, 0, 10_001, 1 days
        );
    }

    function testRejectsZeroOutflowWindow() public {
        vm.expectRevert(bytes("LidoVault: zero outflow window"));
        new LidoStEthExitBufferAssertion(address(vault), address(stEth), address(wstEth), address(0), 0, 0, 5_000, 0);
    }

    function testDeploys() public {
        LidoStEthExitBufferAssertion assertion = new LidoStEthExitBufferAssertion(
            address(vault), address(stEth), address(wstEth), address(receipt), 1 ether, 500, 5_000, 1 days
        );
        assertTrue(address(assertion) != address(0));
    }
}
