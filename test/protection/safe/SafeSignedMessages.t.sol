// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeFixture, SafeStorageWriter} from "./SafeFixture.sol";
import {SafeConfigLockAssertion} from "../../../src/protection/safe/SafeConfigLockAssertion.sol";
import {SafeTxShapeAssertion} from "../../../src/protection/safe/SafeTxShapeAssertion.sol";
import {SafeTxShapeHelpers} from "../../../src/protection/safe/SafeTxShapeHelpers.sol";

interface IMessageSafe {
    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4);
    function signedMessages(bytes32 digest) external view returns (uint256);
}

interface IMessageHandler {
    function getMessageHashForSafe(address safe, bytes memory message) external view returns (bytes32);
}

contract SafeSignedMessagesTest is SafeFixture {
    bytes32 internal constant MESSAGE = keccak256("downstream authorization");
    address internal handler;
    address internal signingLibrary;

    function testConfigLockAllowsOwnerAndModuleSigning() public {
        for (uint256 version; version < 2; ++version) {
            for (uint256 callerKind; callerKind < 2; ++callerKind) {
                _deploySigningSafe(version);
                vm.expectRevert(bytes("Hash not approved"));
                IMessageSafe(address(safe)).isValidSignature(MESSAGE, "");
                _armConfig();
                bytes memory data = abi.encodeWithSignature("signMessage(bytes)", abi.encode(MESSAGE));
                if (callerKind == 0) assertTrue(_ownerCall(signingLibrary, data, 1));
                else assertTrue(_moduleCall(signingLibrary, data, 1));
                assertEq(IMessageSafe(address(safe)).isValidSignature(MESSAGE, ""), bytes4(0x1626ba7e));
                vm.expectRevert(bytes("Hash not approved"));
                IMessageSafe(address(safe)).isValidSignature(keccak256("different message"), "");
            }
        }
    }

    function testConfigLockAllowsPrecomputedSignedMessageSlot() public {
        for (uint256 version; version < 2; ++version) {
            _deploySigningSafe(version);
            bytes32 digest = IMessageHandler(handler).getMessageHashForSafe(address(safe), abi.encode(MESSAGE));
            bytes32 slot = keccak256(abi.encode(digest, uint256(7)));
            _armConfig();
            assertTrue(
                _moduleCall(address(writer), abi.encodeCall(SafeStorageWriter.write, (slot, bytes32(uint256(1)))), 1)
            );
            assertEq(IMessageSafe(address(safe)).signedMessages(digest), 1);
            assertEq(IMessageSafe(address(safe)).isValidSignature(MESSAGE, ""), bytes4(0x1626ba7e));
        }
    }

    function testBlanketDelegatecallPolicyAlsoBlocksOwnerSigning() public {
        for (uint256 version; version < 2; ++version) {
            _deploySigningSafe(version);
            // Work around PCL's exactly-one assertion count for proxy function triggers.
            vm.etch(address(safe), singleton.code);
            SafeTxShapeHelpers.TargetPolicy[] memory targets = new SafeTxShapeHelpers.TargetPolicy[](1);
            targets[0] = SafeTxShapeHelpers.TargetPolicy(signingLibrary, true, false, false, false);
            cl.assertion(
                address(safe),
                abi.encodePacked(
                    type(SafeTxShapeAssertion).creationCode,
                    abi.encode(
                        targets,
                        new SafeTxShapeHelpers.SelectorPolicy[](0),
                        new SafeTxShapeHelpers.BatchExecutorPolicy[](0),
                        new SafeTxShapeHelpers.ApprovalPolicy[](0),
                        true,
                        _oneAddress(module)
                    )
                ),
                SafeTxShapeAssertion.assertSafeDelegateCallPolicy.selector
            );
            vm.expectRevert(
                abi.encodeWithSelector(SafeTxShapeHelpers.SafeTxShapeDelegateCallBlocked.selector, signingLibrary)
            );
            _ownerCall(signingLibrary, abi.encodeWithSignature("signMessage(bytes)", abi.encode(MESSAGE)), 1);
        }
    }

    function _deploySigningSafe(uint256 version) internal {
        handler = deployCode(
            version == 0
                ? "lib/safe-smart-account-1.3.0/contracts/handler/CompatibilityFallbackHandler.sol:CompatibilityFallbackHandler"
                : "lib/safe-smart-account-1.4.0/contracts/handler/CompatibilityFallbackHandler.sol:CompatibilityFallbackHandler"
        );
        signingLibrary = deployCode(
            version == 0
                ? "lib/safe-smart-account-1.3.0/contracts/examples/libraries/SignMessage.sol:SignMessageLib"
                : "lib/safe-smart-account-1.4.0/contracts/libraries/SignMessageLib.sol:SignMessageLib"
        );
        _deploy(version, handler);
    }

    function _armConfig() internal {
        cl.assertion(
            address(safe),
            abi.encodePacked(
                type(SafeConfigLockAssertion).creationCode,
                abi.encode(
                    1,
                    1,
                    _oneHash(keccak256(abi.encode(_oneAddress(owner)))),
                    _oneHash(keccak256(abi.encode(_oneAddress(module)))),
                    address(0),
                    address(0),
                    handler,
                    _oneAddress(singleton)
                )
            ),
            SafeConfigLockAssertion.assertSafeConfiguration.selector
        );
    }
}
