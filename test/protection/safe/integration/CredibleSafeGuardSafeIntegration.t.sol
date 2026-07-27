// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {GnosisSafe as GnosisSafe130} from "../../../../lib/safe-smart-account-1.3.0/contracts/GnosisSafe.sol";
import {
    GnosisSafeProxyFactory as GnosisSafeProxyFactory130
} from "../../../../lib/safe-smart-account-1.3.0/contracts/proxies/GnosisSafeProxyFactory.sol";
import {Safe as Safe140} from "../../../../lib/safe-smart-account-1.4.0/contracts/Safe.sol";
import {
    SafeProxyFactory as SafeProxyFactory140
} from "../../../../lib/safe-smart-account-1.4.0/contracts/proxies/SafeProxyFactory.sol";
import {Safe as Safe141} from "../../../../lib/safe-smart-account/contracts/Safe.sol";
import {
    SafeProxyFactory as SafeProxyFactory141
} from "../../../../lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe as Safe150} from "../../../../lib/safe-smart-account-1.5.0/contracts/Safe.sol";
import {
    SafeProxyFactory as SafeProxyFactory150
} from "../../../../lib/safe-smart-account-1.5.0/contracts/proxies/SafeProxyFactory.sol";

import {CredibleSafeGuard} from "credible-std/protection/safe/CredibleSafeGuard.sol";
import {CredibleRegistryMock} from "./mocks/CredibleRegistryMock.sol";

/// @dev Stable owner-transaction ABI shared by every guard-capable Safe release in the matrix.
///      Enum.Operation is represented by its ABI type (`uint8`) so the harness does not depend on
///      any one release's Enum library.
interface ISafe {
    function VERSION() external view returns (string memory);

    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function nonce() external view returns (uint256);

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool success);

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) external view returns (bytes32);
}

/// @notice Shared lifecycle suite for every guard-capable Safe release from 1.3.0 through 1.5.0.
/// @dev Concrete adapters below deploy each release's real singleton and proxy factory. All setup,
///      hashing, signing, execution, and guard-slot inspection use the stable Safe ABI above.
abstract contract CredibleSafeGuardSafeIntegrationTest is Test {
    /// @dev Safe stores the transaction guard at keccak256("guard_manager.guard.address").
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    uint8 internal constant CALL = 0;
    uint256 internal constant FAIL_OPEN_BLOCK_THRESHOLD = 75;
    uint256 internal constant BASE_BLOCK = 1_000_000;
    address internal constant PROTOCOL_MANAGER = address(0xA11CE);

    uint256 internal ownerPk = uint256(keccak256("safe.owner"));
    address internal owner;

    CredibleRegistryMock internal registry;
    CredibleSafeGuard internal guard;
    ISafe internal safe;

    function setUp() public {
        owner = vm.addr(ownerPk);

        registry = new CredibleRegistryMock();
        guard = new CredibleSafeGuard(registry, FAIL_OPEN_BLOCK_THRESHOLD, PROTOCOL_MANAGER);

        address[] memory owners = new address[](1);
        owners[0] = owner;
        bytes memory initializer =
            abi.encodeCall(ISafe.setup, (owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))));
        safe = ISafe(payable(_deploySafe(initializer)));

        assertEq(safe.VERSION(), _expectedVersion(), "unexpected Safe version");

        vm.roll(BASE_BLOCK);

        // `setGuard` is self-authorized, so install it through an owner-signed Safe transaction.
        // Safe 1.4.0+ also run their real GS300 ERC-165 interface check during this call.
        assertTrue(_setGuard(address(guard)), "guard installation failed");
        assertEq(_installedGuard(), address(guard), "guard not installed");
    }

    function _deploySafe(bytes memory initializer) internal virtual returns (address);

    function _expectedVersion() internal pure virtual returns (string memory);

    function test_guardInstalledThroughOwnerSignedSelfTransaction() public view {
        assertEq(safe.nonce(), 1);
        assertEq(_installedGuard(), address(guard));
    }

    function test_executesInCredibleBlock() public {
        registry.markCurrentBlockCredible();

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));

        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(guard));
    }

    function test_revertsInNonCredibleBlockWithinWindow() public {
        registry.setLastCredibleBlock(block.number - 1);

        uint256 nonceBefore = safe.nonce();
        bytes memory sig = _signTx(owner, 0, "");

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(owner, 0, "", CALL, 0, 0, 0, address(0), payable(address(0)), sig);

        assertEq(safe.nonce(), nonceBefore, "blocked transaction consumed nonce");
        assertEq(_installedGuard(), address(guard));
    }

    function test_regularTransactionBlockedAtFailOpenThresholdBoundary() public {
        registry.setLastCredibleBlock(block.number - FAIL_OPEN_BLOCK_THRESHOLD);

        uint256 nonceBefore = safe.nonce();
        bytes memory sig = _signTx(owner, 0, "");

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(owner, 0, "", CALL, 0, 0, 0, address(0), payable(address(0)), sig);

        assertEq(safe.nonce(), nonceBefore, "boundary transaction consumed nonce");
        assertEq(_installedGuard(), address(guard));
    }

    function test_guardRemovalBlockedInNonCredibleBlockWithinWindow() public {
        registry.setLastCredibleBlock(block.number - 1);

        uint256 nonceBefore = safe.nonce();
        bytes memory data = _setGuardData(address(0));
        bytes memory sig = _signTx(address(safe), 0, data);

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(address(safe), 0, data, CALL, 0, 0, 0, address(0), payable(address(0)), sig);

        assertEq(safe.nonce(), nonceBefore, "blocked removal consumed nonce");
        assertEq(_installedGuard(), address(guard), "blocked removal changed guard");
    }

    function test_guardRemovalBlockedAtFailOpenThresholdBoundary() public {
        registry.setLastCredibleBlock(block.number - FAIL_OPEN_BLOCK_THRESHOLD);

        uint256 nonceBefore = safe.nonce();
        bytes memory data = _setGuardData(address(0));
        bytes memory sig = _signTx(address(safe), 0, data);

        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(address(safe), 0, data, CALL, 0, 0, 0, address(0), payable(address(0)), sig);

        assertEq(safe.nonce(), nonceBefore, "boundary removal consumed nonce");
        assertEq(_installedGuard(), address(guard), "boundary removal changed guard");
    }

    function test_ownerSignedGuardRemovalSucceedsAfterFailOpenThreshold() public {
        registry.setLastCredibleBlock(block.number - (FAIL_OPEN_BLOCK_THRESHOLD + 1));

        uint256 nonceBefore = safe.nonce();
        assertTrue(_setGuard(address(0)), "expired guard removal failed");

        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(0));
    }

    function test_ownerSignedGuardRemovalBeforeExpirySucceedsInCredibleBlock() public {
        registry.markCurrentBlockCredible();

        uint256 nonceBefore = safe.nonce();
        assertTrue(_setGuard(address(0)), "credible guard removal failed");

        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(0));
    }

    function test_regularTransactionSucceedsAfterFailOpenThreshold() public {
        registry.setLastCredibleBlock(block.number - (FAIL_OPEN_BLOCK_THRESHOLD + 1));

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));

        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(guard));
    }

    function test_failsOpenWhenCredibilityReadReverts() public {
        vm.mockCallRevert(
            address(registry), abi.encodeWithSignature("isCredibleBlock(uint256)", block.number), "registry unavailable"
        );

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_canRemoveGuardWhenRegistryReadReverts() public {
        vm.mockCallRevert(
            address(registry), abi.encodeWithSignature("isCredibleBlock(uint256)", block.number), "registry unavailable"
        );

        uint256 nonceBefore = safe.nonce();
        assertTrue(_setGuard(address(0)), "recovery removal failed");

        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(0));
    }

    function test_failsOpenWhenCredibilityReadIsMalformed() public {
        _mockMalformedCredibilityRead();

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_canRemoveGuardWhenCredibilityReadIsMalformed() public {
        _mockMalformedCredibilityRead();

        uint256 nonceBefore = safe.nonce();
        assertTrue(_setGuard(address(0)), "malformed-response recovery removal failed");

        assertEq(safe.nonce(), nonceBefore + 1);
        assertEq(_installedGuard(), address(0));
    }

    function test_failsOpenWhenLastBlockReadReverts() public {
        vm.mockCallRevert(address(registry), abi.encodeWithSignature("lastCredibleBlock()"), "registry unavailable");

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_failsOpenWhenLastBlockReportedInFuture() public {
        registry.setLastCredibleBlock(type(uint256).max);

        uint256 nonceBefore = safe.nonce();
        assertTrue(_execSafeTx(owner, 0, ""));
        assertEq(safe.nonce(), nonceBefore + 1);
    }

    function test_endToEndStallThenRecover() public {
        registry.markCurrentBlockCredible();
        assertTrue(_execSafeTx(owner, 0, ""));

        vm.roll(block.number + 10);
        bytes memory sig = _signTx(owner, 0, "");
        vm.expectRevert(CredibleSafeGuard.NonCredibleBlock.selector);
        safe.execTransaction(owner, 0, "", CALL, 0, 0, 0, address(0), payable(address(0)), sig);

        vm.roll(block.number + FAIL_OPEN_BLOCK_THRESHOLD);
        assertTrue(_execSafeTx(owner, 0, ""));

        registry.markCurrentBlockCredible();
        assertTrue(_execSafeTx(owner, 0, ""));
    }

    /// @dev Signs a single-owner Safe transaction (CALL, no gas refund) over the current nonce.
    function _signTx(address to, uint256 value, bytes memory data) internal view returns (bytes memory) {
        bytes32 txHash = safe.getTransactionHash(to, value, data, CALL, 0, 0, 0, address(0), address(0), safe.nonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, txHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Signs and submits a Safe transaction; reverts bubble up to the caller.
    function _execSafeTx(address to, uint256 value, bytes memory data) internal returns (bool) {
        bytes memory sig = _signTx(to, value, data);
        return safe.execTransaction(to, value, data, CALL, 0, 0, 0, address(0), payable(address(0)), sig);
    }

    function _setGuard(address newGuard) internal returns (bool) {
        return _execSafeTx(address(safe), 0, _setGuardData(newGuard));
    }

    function _setGuardData(address newGuard) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("setGuard(address)", newGuard);
    }

    function _mockMalformedCredibilityRead() internal {
        vm.mockCall(
            address(registry), abi.encodeWithSignature("isCredibleBlock(uint256)", block.number), abi.encode(uint256(2))
        );
    }

    function _installedGuard() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(safe), GUARD_STORAGE_SLOT))));
    }
}

contract CredibleSafeGuardSafe130IntegrationTest is CredibleSafeGuardSafeIntegrationTest {
    function _deploySafe(bytes memory initializer) internal override returns (address) {
        GnosisSafe130 singleton = new GnosisSafe130();
        GnosisSafeProxyFactory130 factory = new GnosisSafeProxyFactory130();
        return address(factory.createProxyWithNonce(address(singleton), initializer, 0));
    }

    function _expectedVersion() internal pure override returns (string memory) {
        return "1.3.0";
    }
}

contract CredibleSafeGuardSafe140IntegrationTest is CredibleSafeGuardSafeIntegrationTest {
    function _deploySafe(bytes memory initializer) internal override returns (address) {
        Safe140 singleton = new Safe140();
        SafeProxyFactory140 factory = new SafeProxyFactory140();
        return address(factory.createProxyWithNonce(address(singleton), initializer, 0));
    }

    function _expectedVersion() internal pure override returns (string memory) {
        return "1.4.0";
    }
}

contract CredibleSafeGuardSafe141IntegrationTest is CredibleSafeGuardSafeIntegrationTest {
    function _deploySafe(bytes memory initializer) internal override returns (address) {
        Safe141 singleton = new Safe141();
        SafeProxyFactory141 factory = new SafeProxyFactory141();
        return address(factory.createProxyWithNonce(address(singleton), initializer, 0));
    }

    function _expectedVersion() internal pure override returns (string memory) {
        return "1.4.1";
    }
}

contract CredibleSafeGuardSafe150IntegrationTest is CredibleSafeGuardSafeIntegrationTest {
    function _deploySafe(bytes memory initializer) internal override returns (address) {
        Safe150 singleton = new Safe150();
        SafeProxyFactory150 factory = new SafeProxyFactory150();
        return address(factory.createProxyWithNonce(address(singleton), initializer, 0));
    }

    function _expectedVersion() internal pure override returns (string memory) {
        return "1.5.0";
    }
}
