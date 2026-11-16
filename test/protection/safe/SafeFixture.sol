// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CredibleTest} from "../../../src/CredibleTest.sol";

interface IRealSafe {
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
    function isModuleEnabled(address) external view returns (bool);
    function getModulesPaginated(address, uint256) external view returns (address[] memory, address);
    function VERSION() external view returns (string memory);
}

contract SafeStorageWriter {
    function write(bytes32 slot, bytes32 value) external {
        assembly { sstore(slot, value) }
    }

    function replaceAndRestore(address replacement) external {
        bytes32 original;
        assembly {
            original := sload(0)
            sstore(0, replacement)
        }
        // Exercise the replacement before restoring the original implementation.
        IRealSafe(address(this)).VERSION();
        assembly { sstore(0, original) }
    }
}

abstract contract SafeFixture is Test, CredibleTest {
    IRealSafe internal safe;
    address internal singleton;
    address internal owner = address(0xA11CE);
    address internal module = address(0xB0B);
    SafeStorageWriter internal writer;

    function _deploy(uint256 version, address handler) internal {
        string memory root = version == 0
            ? "lib/safe-smart-account-1.3.0/contracts/"
            : version == 1
                ? "lib/safe-smart-account-1.4.0/contracts/"
                : version == 2 ? "lib/safe-smart-account/contracts/" : "lib/safe-smart-account-1.5.0/contracts/";
        singleton = deployCode(string.concat(root, version == 0 ? "GnosisSafe.sol:GnosisSafe" : "Safe.sol:Safe"));
        safe = IRealSafe(
            deployCode(
                string.concat(
                    root,
                    version == 0 ? "proxies/GnosisSafeProxy.sol:GnosisSafeProxy" : "proxies/SafeProxy.sol:SafeProxy"
                ),
                abi.encode(singleton)
            )
        );
        address[] memory owners = new address[](1);
        owners[0] = owner;
        safe.setup(owners, 1, address(0), "", handler, address(0), 0, payable(address(0)));
        assertTrue(_ownerCall(address(safe), abi.encodeCall(IRealSafe.enableModule, (module)), 0));
        writer = new SafeStorageWriter();
    }

    function _ownerCall(address to, bytes memory data, uint8 operation) internal returns (bool) {
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));
        vm.prank(owner);
        return safe.execTransaction(to, 0, data, operation, 0, 0, 0, address(0), payable(address(0)), signature);
    }

    function _moduleCall(address to, bytes memory data, uint8 operation) internal returns (bool) {
        vm.prank(module);
        return safe.execTransactionFromModule(to, 0, data, operation);
    }

    function _oneAddress(address account) internal pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }

    function _oneHash(bytes32 value) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = value;
    }
}
