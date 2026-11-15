// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";
import {SafeConfigLockAssertion} from "../../../src/protection/safe/SafeConfigLockAssertion.sol";
import {SafeTxShapeAssertion} from "../../../src/protection/safe/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../../src/protection/safe/SafeTxShapeHelpers.sol";

interface ISigningSafe {
    function setup(address[] calldata, uint256, address, bytes calldata, address, address, uint256, address payable)
        external;
    function execTransaction(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes calldata
    ) external returns (bool);
    function execTransactionFromModule(address, uint256, bytes calldata, uint8) external returns (bool);
    function execTransactionFromModuleReturnData(address, uint256, bytes calldata, uint8)
        external
        returns (bool, bytes memory);
    function enableModule(address) external;
    function disableModule(address, address) external;
    function setGuard(address) external;
    function isValidSignature(bytes32, bytes calldata) external view returns (bytes4);
    function signedMessages(bytes32) external view returns (uint256);
    function VERSION() external view returns (string memory);
}

interface ISigningHandler {
    function getMessageHashForSafe(address, bytes calldata) external view returns (bytes32);
}

contract MessageStorageWriter {
    function write(bytes32 slot) external {
        assembly { sstore(slot, 1) }
    }
}

abstract contract SafeSignedMessagesTest is Test, CredibleTest {
    bytes32 internal constant MESSAGE = keccak256("approve downstream transaction 73");
    bytes4 internal constant MAGIC = 0x1626ba7e;
    uint256 internal constant OWNER_KEY = 6173;
    address internal owner;
    address internal constant MODULE = address(0xB0B);
    ISigningSafe internal safe;
    address internal singleton;
    address internal signingLibrary;
    address internal handler;
    MessageStorageWriter internal writer;

    function _root() internal pure virtual returns (string memory);
    function _version() internal pure virtual returns (string memory);

    function setUp() public {
        string memory root = _root();
        bool legacy = keccak256(bytes(_version())) == keccak256("1.3.0");
        owner = vm.addr(OWNER_KEY);
        handler =
            deployCode(string.concat(root, "handler/CompatibilityFallbackHandler.sol:CompatibilityFallbackHandler"));
        signingLibrary = deployCode(
            string.concat(
                root,
                legacy
                    ? "examples/libraries/SignMessage.sol:SignMessageLib"
                    : "libraries/SignMessageLib.sol:SignMessageLib"
            )
        );
        singleton = deployCode(string.concat(root, legacy ? "GnosisSafe.sol:GnosisSafe" : "Safe.sol:Safe"));
        safe = ISigningSafe(
            deployCode(
                string.concat(
                    root, legacy ? "proxies/GnosisSafeProxy.sol:GnosisSafeProxy" : "proxies/SafeProxy.sol:SafeProxy"
                ),
                abi.encode(singleton)
            )
        );
        safe.setup(_one(owner), 1, address(0), "", handler, address(0), 0, payable(address(0)));
        assertEq(safe.VERSION(), _version());
        assertTrue(_ownerCall(address(safe), abi.encodeCall(ISigningSafe.enableModule, (MODULE)), 0));
        writer = new MessageStorageWriter();
    }

    function testRealProxyOwnerSignaturesAndStoredApprovals() public virtual {
        bytes32 digest = ISigningHandler(handler).getMessageHashForSafe(address(safe), abi.encode(MESSAGE));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(safe.isValidSignature(MESSAGE, signature), MAGIC);
        assertEq(safe.signedMessages(digest), 0);
        vm.expectRevert();
        safe.isValidSignature(keccak256("another message"), signature);

        _armConfig();
        assertTrue(_ownerCall(signingLibrary, _signingData(MESSAGE), 1));
        assertEq(safe.signedMessages(digest), 1);
        assertEq(safe.isValidSignature(MESSAGE, ""), MAGIC);
        vm.expectRevert(bytes("Hash not approved"));
        safe.isValidSignature(keccak256("another message"), "");
    }

    // Evidence control: the config lock alone is not the signed-message policy.
    // These calls retain the real proxy runtime and exercise storage triggers.
    function testRealProxyConfigLockAllowsModuleAndPrecomputedApprovals() public {
        _armConfig();
        vm.prank(MODULE);
        assertTrue(safe.execTransactionFromModule(signingLibrary, 0, _signingData(MESSAGE), 1));
        assertEq(safe.isValidSignature(MESSAGE, ""), MAGIC);

        bytes32 other = keccak256("precomputed approval");
        bytes32 slot = _messageSlot(other);
        _armConfig();
        vm.prank(MODULE);
        assertTrue(
            safe.execTransactionFromModule(address(writer), 0, abi.encodeCall(MessageStorageWriter.write, (slot)), 1)
        );
        assertEq(safe.isValidSignature(other, ""), MAGIC);
    }

    function testOwnerStoredApprovalPassesEveryShapePolicy() public virtual {
        _assertOwnerSigningPasses();
    }

    function _assertOwnerSigningPasses() internal {
        bytes4[5] memory checks = [
            SafeTxShapeAssertion.assertSafeModulePolicy.selector,
            SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector,
            SafeTxShapeAssertion.assertSafeTargetSelectorPolicy.selector,
            SafeTxShapeAssertion.assertSafeBatchPolicy.selector,
            SafeTxShapeAssertion.assertSafeApprovalPolicy.selector
        ];
        for (uint256 i; i < checks.length; ++i) {
            bytes32 message = keccak256(abi.encode(MESSAGE, i));
            vm.expectRevert(bytes("Hash not approved"));
            safe.isValidSignature(message, "");
            _arm(checks[i]);
            assertTrue(_ownerCall(signingLibrary, _signingData(message), 1));
            assertEq(safe.isValidSignature(message, ""), MAGIC);
            vm.expectRevert(bytes("Hash not approved"));
            safe.isValidSignature(keccak256(abi.encode(message)), "");
        }
    }

    function testModuleCannotUseOwnerSigningException() public {
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(
            abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, signingLibrary)
        );
        vm.prank(MODULE);
        safe.execTransactionFromModule(signingLibrary, 0, _signingData(MESSAGE), 1);
    }

    function testModuleReturnDataCannotUseOwnerSigningException() public {
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(
            abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, signingLibrary)
        );
        vm.prank(MODULE);
        safe.execTransactionFromModuleReturnData(signingLibrary, 0, _signingData(MESSAGE), 1);
    }

    function testOwnerPrecomputedWriteBlocked() public {
        _assertPrecomputedWriteBlocked(0);
    }

    function testModulePrecomputedWriteBlocked() public {
        _assertPrecomputedWriteBlocked(1);
    }

    function testModuleReturnDataPrecomputedWriteBlocked() public {
        _assertPrecomputedWriteBlocked(2);
    }

    function _assertPrecomputedWriteBlocked(uint8 kind) internal {
        // A failing PCL assertion ends the test frame. Keep each entrypoint in its
        // own test rather than putting rejection checks in a loop.
        bytes32 slot = _messageSlot(MESSAGE);
        bytes memory payload = abi.encodeCall(MessageStorageWriter.write, (slot));
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(
            abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, address(writer))
        );
        if (kind == 0) {
            _ownerCall(address(writer), payload, 1);
        } else if (kind == 1) {
            vm.prank(MODULE);
            safe.execTransactionFromModule(address(writer), 0, payload, 1);
        } else {
            vm.prank(MODULE);
            safe.execTransactionFromModuleReturnData(address(writer), 0, payload, 1);
        }
    }

    function testSameSelectorAtUnlistedLibraryIsBlocked() public {
        string memory root = _root();
        address otherLibrary = deployCode(
            string.concat(
                root,
                keccak256(bytes(_version())) == keccak256("1.3.0")
                    ? "examples/libraries/SignMessage.sol:SignMessageLib"
                    : "libraries/SignMessageLib.sol:SignMessageLib"
            )
        );
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(
            abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, otherLibrary)
        );
        _ownerCall(otherLibrary, _signingData(MESSAGE), 1);
    }

    function testOtherSelectorAtListedLibraryIsBlocked() public {
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(
            abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, signingLibrary)
        );
        _ownerCall(signingLibrary, abi.encodeWithSignature("getMessageHash(bytes)", abi.encode(MESSAGE)), 1);
    }

    function testTrailingDataDoesNotWidenSigningException() public {
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(SafeTxShapeHelpers.SafeTxShapeBatchPayloadMalformed.selector);
        _ownerCall(signingLibrary, bytes.concat(_signingData(MESSAGE), hex"01"), 1);
    }

    function testOwnerSigningRejectsNonzeroDeclaredValue() public {
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(
            abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, signingLibrary)
        );
        vm.prank(owner);
        safe.execTransaction(
            signingLibrary, 1, _signingData(MESSAGE), 1, 0, 0, 0, address(0), payable(address(0)), signature
        );
    }

    function testOwnerSigningBatchIsNotImplicitlyAllowlisted() public {
        address multiSend = deployCode("lib/safe-smart-account/contracts/libraries/MultiSend.sol:MultiSend");
        bytes memory packed = abi.encodePacked(
            uint8(1), signingLibrary, uint256(0), uint256(_signingData(MESSAGE).length), _signingData(MESSAGE)
        );
        _arm(SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector);
        vm.expectRevert(abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, multiSend));
        _ownerCall(multiSend, abi.encodeWithSignature("multiSend(bytes)", packed), 1);
    }

    function _messageSlot(bytes32 message) internal view returns (bytes32) {
        bytes32 digest = ISigningHandler(handler).getMessageHashForSafe(address(safe), abi.encode(message));
        return keccak256(abi.encode(digest, uint256(7)));
    }

    function _armConfig() internal virtual {
        bytes32[] memory owners = new bytes32[](1);
        owners[0] = keccak256(abi.encode(_one(owner)));
        bytes32[] memory modules = new bytes32[](1);
        modules[0] = keccak256(abi.encode(_one(MODULE)));
        cl.assertion(
            address(safe),
            abi.encodePacked(
                type(SafeConfigLockAssertion).creationCode,
                abi.encode(1, 1, owners, modules, address(0), address(0), handler)
            ),
            SafeConfigLockAssertion.assertSafeConfiguration.selector
        );
    }

    function _arm(bytes4 check) internal {
        // PCL counts both the proxy CALL and singleton DELEGATECALL as function
        // triggers, but cl.assertion insists on exactly one execution. Exercise the
        // production singleton against initialized Safe storage here; the real
        // proxy controls above deliberately do not use this workaround.
        vm.etch(address(safe), singleton.code);
        SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
        targets[0] = SafeTxShapeHelpers.TargetPolicy(signingLibrary, false, false, false, false);
        cl.assertion(
            address(safe),
            abi.encodePacked(
                type(SafeTxShapeAssertion).creationCode,
                abi.encode(
                    targets,
                    new SafeTxShapeHelpers.SelectorPolicy[](0),
                    new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
                    new SafeTxShapeHelpers.ApprovalPolicy[](0),
                    false,
                    new address[](0),
                    _one(signingLibrary)
                )
            ),
            check
        );
    }

    function _ownerCall(address target, bytes memory data, uint8 operation) internal returns (bool) {
        // Safe's approved-hash signature is only accepted because the actual owner submits it.
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));
        vm.prank(owner);
        return safe.execTransaction(target, 0, data, operation, 0, 0, 0, address(0), payable(address(0)), signature);
    }

    function _signingData(bytes32 message) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("signMessage(bytes)", abi.encode(message));
    }

    function _one(address account) internal pure returns (address[] memory result) {
        result = new address[](1);
        result[0] = account;
    }
}

contract SafeSignedMessages130Test is SafeSignedMessagesTest {
    function _root() internal pure override returns (string memory) {
        return "lib/safe-smart-account-1.3.0/contracts/";
    }

    function _version() internal pure override returns (string memory) {
        return "1.3.0";
    }
}

contract SafeSignedMessages140Test is SafeSignedMessagesTest {
    function _root() internal pure override returns (string memory) {
        return "lib/safe-smart-account-1.4.0/contracts/";
    }

    function _version() internal pure override returns (string memory) {
        return "1.4.0";
    }
}

contract SafeSignedMessages141Test is SafeSignedMessagesTest {
    function _root() internal pure override returns (string memory) {
        return "lib/safe-smart-account/contracts/";
    }

    function _version() internal pure override returns (string memory) {
        return "1.4.1";
    }
}

contract SafeSignedMessages150Test is SafeSignedMessagesTest {
    function _root() internal pure override returns (string memory) {
        return "lib/safe-smart-account-1.5.0/contracts/";
    }

    function _version() internal pure override returns (string memory) {
        return "1.5.0";
    }
}
