// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {BalancerV3VaultOutflowAssertion} from "../src/BalancerV3VaultOutflowAssertion.sol";

/// @notice Armed variant: drives the production breaker body through real assertion dispatch.
/// @dev The `watchCumulativeOutflow` trigger itself is executor-driven (rolling-window accounting)
///      and is not simulated by local `pcl test`, so the armed tests substitute a call trigger and
///      dispatch the UNMODIFIED `assertOutflowWithinLimit`, executing the real
///      `ph.getAssertionAdopter()` adopter check instead of a direct call that skips it.
contract ArmedOutflowBreaker is BalancerV3VaultOutflowAssertion {
    constructor(address vault_, address token_, uint256 thresholdBps_, uint256 windowDuration_)
        BalancerV3VaultOutflowAssertion(vault_, token_, thresholdBps_, windowDuration_)
    {}

    function triggers() external view override {
        registerCallTrigger(this.assertOutflowWithinLimit.selector);
    }
}

/// @notice Minimal adopter target for the armed dispatch tests.
contract MockVaultTarget {
    uint256 public pokes;

    function poke() external {
        pokes++;
    }
}

contract BalancerV3VaultOutflowAssertionTest is Test, CredibleTest {
    address internal vault = makeAddr("vault");
    address internal token = makeAddr("token");

    MockVaultTarget internal adopter;

    function setUp() public {
        adopter = new MockVaultTarget();
    }

    function _armOn(address adopterAddress, address configuredVault) internal {
        bytes memory createData = abi.encodePacked(
            type(ArmedOutflowBreaker).creationCode, abi.encode(configuredVault, token, 2_000, uint256(1 days))
        );
        cl.assertion(adopterAddress, createData, BalancerV3VaultOutflowAssertion.assertOutflowWithinLimit.selector);
    }

    // --- dispatched breaker behavior ---------------------------------------

    /// @notice Adopter matches the configured Vault: the breaker's unconditional revert fires
    ///         through real assertion dispatch.
    function testDispatchedBreakerReverts() public {
        _armOn(address(adopter), address(adopter));
        vm.expectRevert(bytes("BalancerV3Outflow: vault token outflow circuit breaker tripped"));
        adopter.poke();
    }

    /// @notice Adopter does NOT match the configured Vault: the flow watcher would be tracking the
    ///         wrong account's balance, so the misconfiguration fails loudly with its own message
    ///         instead of masquerading as a legitimate breaker trip.
    function testDispatchedBreakerRejectsWrongAdopter() public {
        _armOn(address(adopter), vault);
        vm.expectRevert(bytes("BalancerV3Outflow: configured vault is not adopter"));
        adopter.poke();
    }

    // --- constructor guards --------------------------------------------------

    function testRejectsZeroVault() public {
        vm.expectRevert(bytes("BalancerV3Outflow: zero vault"));
        new BalancerV3VaultOutflowAssertion(address(0), token, 2_000, 1 days);
    }

    function testRejectsZeroToken() public {
        vm.expectRevert(bytes("BalancerV3Outflow: zero token"));
        new BalancerV3VaultOutflowAssertion(vault, address(0), 2_000, 1 days);
    }

    function testRejectsZeroThreshold() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad threshold"));
        new BalancerV3VaultOutflowAssertion(vault, token, 0, 1 days);
    }

    /// @notice 10_000 bps is rejected, not merely discouraged: the executor dispatches only when
    ///         net outflow STRICTLY exceeds the threshold and a full drain lands exactly on 100%,
    ///         so a 100% setting could never fire — the breaker would be silently disabled.
    function testRejectsFullDrainThreshold() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad threshold"));
        new BalancerV3VaultOutflowAssertion(vault, token, 10_000, 1 days);
    }

    function testAcceptsMaximumEnforceableThreshold() public {
        new BalancerV3VaultOutflowAssertion(vault, token, 9_999, 1 days);
    }

    /// @notice Windows below the executor's 10-second bucket deploy fine but then fail trigger
    ///         registration; the constructor mirrors the executor bound so the mistake surfaces at
    ///         deploy time.
    function testRejectsWindowBelowExecutorBucket() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad window"));
        new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 9);
    }

    function testRejectsZeroWindow() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad window"));
        new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 0);
    }

    /// @notice Windows that do not fit the executor's u64 window state are rejected for the same
    ///         deploy-time-visibility reason.
    function testRejectsWindowBeyondUint64() public {
        vm.expectRevert(bytes("BalancerV3Outflow: bad window"));
        new BalancerV3VaultOutflowAssertion(vault, token, 2_000, uint256(type(uint64).max) + 1);
    }

    function testAcceptsExecutorWindowBounds() public {
        new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 10);
        new BalancerV3VaultOutflowAssertion(vault, token, 2_000, type(uint64).max);
    }

    function testDeploys() public {
        BalancerV3VaultOutflowAssertion assertion = new BalancerV3VaultOutflowAssertion(vault, token, 2_000, 1 days);
        assertTrue(address(assertion) != address(0));
    }
}
