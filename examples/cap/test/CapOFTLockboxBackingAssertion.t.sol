// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {CredibleTest} from "../../../src/CredibleTest.sol";
import {CapOFTLockboxBackingAssertion} from "../src/CapOFTLockboxBackingAssertion.sol";

/// @notice OFTAdapter stand-in holding locked cUSD. Releases only inside `lzReceive`
///         (mimicking LayerZero's endpoint-only guard); `drain` models an unauthorized exit.
///         Messages use the OFT codec: `sendTo` (bytes32) ++ `amountSD` (uint64, 6 shared
///         decimals). A `releaseMultiplier` above 1 models a faulty/upgraded adapter that
///         releases more than the verified message authorizes.
contract MockLockbox {
    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    /// @dev 18 local decimals, 6 shared decimals.
    uint256 internal constant RATE = 1e12;

    ERC20Mock internal immutable TOKEN;
    address internal immutable ENDPOINT;
    uint256 internal immutable RELEASE_MULTIPLIER;

    constructor(address token_, address endpoint_, uint256 releaseMultiplier_) {
        TOKEN = ERC20Mock(token_);
        ENDPOINT = endpoint_;
        RELEASE_MULTIPLIER = releaseMultiplier_;
    }

    /// @dev Standard OFTAdapter credit: release locked tokens to the remote-burn recipient.
    function lzReceive(Origin calldata, bytes32, bytes calldata message, address, bytes calldata) external {
        require(msg.sender == ENDPOINT, "not endpoint");
        address to = address(uint160(uint256(bytes32(message[0:32]))));
        uint256 amount = uint256(uint64(bytes8(message[32:40]))) * RATE;
        TOKEN.transfer(to, amount * RELEASE_MULTIPLIER);
    }

    /// @dev Unauthorized release path (compromised owner / faulty function / stale approval).
    function drain(address to, uint256 amount) external {
        TOKEN.transfer(to, amount);
    }
}

/// @notice Trusted LayerZero endpoint stand-in that drives verified receives.
contract MockEndpoint {
    function deliver(address lockbox, address to, uint256 amount) external {
        bytes memory message = abi.encodePacked(bytes32(uint256(uint160(to))), uint64(amount / 1e12));
        MockLockbox(lockbox)
            .lzReceive(
                MockLockbox.Origin({srcEid: 1, sender: bytes32(0), nonce: 1}),
                bytes32(uint256(1)),
                message,
                address(this),
                ""
            );
    }
}

/// @notice Drains the lockbox in the same transaction as a legitimate (dust) bridge-in, modelling
///         the co-occurrence bypass: an attacker rides an unrelated verified `lzReceive` to slip a
///         large unauthorized release past a presence-only check.
contract AttackBundler {
    MockEndpoint internal immutable endpoint;
    MockLockbox internal immutable lockbox;

    constructor(MockEndpoint endpoint_, MockLockbox lockbox_) {
        endpoint = endpoint_;
        lockbox = lockbox_;
    }

    function rideAlong(address recipient, uint256 dust, address attacker, uint256 drainAmount) external {
        endpoint.deliver(address(lockbox), recipient, dust);
        lockbox.drain(attacker, drainAmount);
    }
}

contract CapOFTLockboxBackingAssertionTest is Test, CredibleTest {
    ERC20Mock internal cusd;
    MockEndpoint internal endpoint;
    MockLockbox internal lockbox;

    address internal recipient = makeAddr("recipient");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        cusd = new ERC20Mock();
        endpoint = new MockEndpoint();
        lockbox = new MockLockbox(address(cusd), address(endpoint), 1);
        // 1000 cUSD locked, backing the remote-chain supply.
        cusd.mint(address(lockbox), 1_000e18);
    }

    function _arm(address lockbox_) internal {
        bytes memory createData = abi.encodePacked(
            type(CapOFTLockboxBackingAssertion).creationCode,
            abi.encode(lockbox_, address(cusd), address(endpoint), 1e12)
        );
        cl.assertion(lockbox_, createData, CapOFTLockboxBackingAssertion.assertReleaseOnlyOnReceive.selector);
    }

    function _arm() internal {
        _arm(address(lockbox));
    }

    function testReceiveReleaseAllowed() public {
        _arm();
        // Verified bridge-in: endpoint drives lzReceive, releasing locked cUSD.
        endpoint.deliver(address(lockbox), recipient, 100e18);
    }

    function testUnauthorizedDrainTrips() public {
        _arm();
        vm.expectRevert(bytes("CapLockbox: locked cUSD released beyond verified receives"));
        vm.prank(attacker);
        lockbox.drain(attacker, 100e18);
    }

    function testDrainRidingVerifiedReceiveTrips() public {
        AttackBundler bundler = new AttackBundler(endpoint, lockbox);
        _arm();
        // A 1 cUSD verified bridge-in cannot launder a 500 cUSD drain in the same transaction:
        // reconciling gross outflow against the amount the receive actually released catches it,
        // whereas a presence-only check would have passed.
        vm.expectRevert(bytes("CapLockbox: locked cUSD released beyond verified receives"));
        bundler.rideAlong(recipient, 1e18, attacker, 500e18);
    }

    function testFaultyAdapterOverReleaseTrips() public {
        // A faulty/upgraded adapter releases 500x what the verified message authorizes. Crediting
        // by the message amount (not the adapter's own transfer logs) catches the excess.
        MockLockbox faulty = new MockLockbox(address(cusd), address(endpoint), 500);
        cusd.mint(address(faulty), 1_000e18);
        _arm(address(faulty));
        vm.expectRevert(bytes("CapLockbox: locked cUSD released beyond verified receives"));
        endpoint.deliver(address(faulty), recipient, 1e18);
    }

    function testDeploys() public {
        CapOFTLockboxBackingAssertion assertion =
            new CapOFTLockboxBackingAssertion(address(lockbox), address(cusd), address(endpoint), 1e12);
        assertTrue(address(assertion) != address(0));
    }
}
