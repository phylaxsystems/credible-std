// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {Safe} from "../../../lib/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "../../../lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Enum} from "../../../lib/safe-smart-account/contracts/common/Enum.sol";

import {CredibleSafeGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";
import {CredibleRegistryMock} from "../src/CredibleRegistryMock.sol";

/// @notice End-to-end tests that install {CredibleSafeGuard} on a real Gnosis Safe (v1.4.1) and
///         drive real, owner-signed `execTransaction` calls through the credible, non-credible,
///         and fail-open paths. Installing the guard via `setGuard` also exercises Safe's real
///         `GS300` ERC-165 check against {CredibleSafeGuard.supportsInterface}.
contract CredibleSafeGuardSafeIntegrationTest is Test {
    /// @dev Safe stores the transaction guard at keccak256("guard_manager.guard.address").
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    uint256 internal constant THRESHOLD = 75;
    uint256 internal constant BASE_BLOCK = 1_000_000;
    address internal constant PROTOCOL_MANAGER = address(0xA11CE);

    uint256 internal ownerPk = uint256(keccak256("safe.owner"));
    address internal owner;

    CredibleRegistryMock internal registry;
    CredibleSafeGuard internal guard;
    Safe internal safe;

    function setUp() public {
        owner = vm.addr(ownerPk);

        registry = new CredibleRegistryMock();
        guard = new CredibleSafeGuard(registry, THRESHOLD, PROTOCOL_MANAGER);

        Safe singleton = new Safe();
        SafeProxyFactory factory = new SafeProxyFactory();

        address[] memory owners = new address[](1);
        owners[0] = owner;

        bytes memory initializer =
            abi.encodeCall(Safe.setup, (owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))));
        safe = Safe(payable(address(factory.createProxyWithNonce(address(singleton), initializer, 0))));

        vm.roll(BASE_BLOCK);

        // `setGuard` is `authorized` (callable only by the Safe itself), so route it through a
        // signed `execTransaction`. The guard is not yet active for this call, and Safe runs its
        // real ERC-165 check on our guard while installing it (reverting GS300 if it were wrong).
        bytes memory setGuardData = abi.encodeWithSignature("setGuard(address)", address(guard));
        bytes memory sig = _signTx(address(safe), 0, setGuardData);
        safe.execTransaction(
            address(safe), 0, setGuardData, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig
        );

        assertEq(_installedGuard(), address(guard), "guard not installed");
    }

    function test_realSafe_guardInstalledViaErc165Check() public view {
        // setUp would have reverted with GS300 if supportsInterface were wrong.
        assertEq(_installedGuard(), address(guard));
    }

    function test_realSafe_executesInCredibleBlock() public {
        registry.markCurrentBlockCredible();

        uint256 nonceBefore = safe.nonce();
        bool ok = _execSafeTx(owner, 0, "");

        assertTrue(ok);
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_realSafe_revertsInNonCredibleBlockWithinWindow() public {
        // Last credible block is one behind: builder set still considered live.
        registry.setLastCredibleBlock(block.number - 1);

        uint256 nonceBefore = safe.nonce();
        bytes memory sig = _signTx(owner, 0, "");

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(owner, 0, "", Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig);

        // A reverted Safe transaction does not consume the nonce.
        assertEq(safe.nonce(), nonceBefore);
    }

    function test_realSafe_failsOpenWhenBuilderOffline() public {
        // No credible block within the configured window: fail open and let the Safe transact.
        registry.setLastCredibleBlock(block.number - (THRESHOLD + 1));

        uint256 nonceBefore = safe.nonce();
        bool ok = _execSafeTx(owner, 0, "");

        assertTrue(ok);
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_realSafe_failsOpenWhenCredibilityReadReverts() public {
        vm.mockCallRevert(
            address(registry), abi.encodeWithSignature("isCredibleBlock(uint256)", block.number), "registry unavailable"
        );

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_realSafe_canRemoveGuardWhenRegistryReadReverts() public {
        vm.mockCallRevert(
            address(registry), abi.encodeWithSignature("isCredibleBlock(uint256)", block.number), "registry unavailable"
        );

        bytes memory setGuardData = abi.encodeWithSignature("setGuard(address)", address(0));
        bytes memory sig = _signTx(address(safe), 0, setGuardData);
        uint256 nonceBefore = safe.nonce();

        assertTrue(
            safe.execTransaction(
                address(safe), 0, setGuardData, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig
            )
        );
        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(0));
    }

    function test_realSafe_failsOpenWhenCredibilityReadIsMalformed() public {
        vm.mockCall(
            address(registry), abi.encodeWithSignature("isCredibleBlock(uint256)", block.number), abi.encode(uint256(2))
        );

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_realSafe_failsOpenWhenLastBlockReadReverts() public {
        vm.mockCallRevert(address(registry), abi.encodeWithSignature("lastCredibleBlock()"), "registry unavailable");

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_realSafe_endToEnd_stallThenRecover() public {
        // Builder healthy: current block is credible -> allowed.
        registry.markCurrentBlockCredible();
        assertTrue(_execSafeTx(owner, 0, ""));

        // Builder misses a few blocks but is still within the live window -> blocked.
        vm.roll(block.number + 10);
        bytes memory sig = _signTx(owner, 0, "");
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(owner, 0, "", Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig);

        // Builder stays silent past the window -> fail open -> allowed.
        vm.roll(block.number + THRESHOLD);
        assertTrue(_execSafeTx(owner, 0, ""));

        // Builder recovers and marks the new current block -> allowed again.
        registry.markCurrentBlockCredible();
        assertTrue(_execSafeTx(owner, 0, ""));
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /// @dev Signs a single-owner Safe transaction (CALL, no gas refund) over the current nonce.
    function _signTx(address to, uint256 value, bytes memory data) internal view returns (bytes memory) {
        bytes32 txHash = safe.getTransactionHash(
            to, value, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, txHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Signs and submits a Safe transaction; reverts bubble up to the caller.
    function _execSafeTx(address to, uint256 value, bytes memory data) internal returns (bool) {
        bytes memory sig = _signTx(to, value, data);
        return safe.execTransaction(to, value, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig);
    }

    function _installedGuard() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(safe), GUARD_STORAGE_SLOT))));
    }
}
