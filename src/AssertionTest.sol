// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {Assertion} from "./Assertion.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";

interface VmEx is Vm {
    function assertionEx(bytes calldata tx, address assertionAdopter, bytes[] calldata assertions)
        external
        returns (bool success);
}

contract ProtocolProxy {
    address immutable adopter;
    Phylax immutable phylax;
    bytes32 constant ENABLED_SLOT = 0x9713f5d7f9ac983a30f5b8db71dacb0e1122f626e053471b5a2d55468c0e3f57; // keccak256("enabled")
    bytes32 constant RESULT_SLOT = 0x9713f5d7f9ac983a30f5b8db71dacb0e1122f626e053471b5a2d55468c0e3f57; // keccak256("result")

    constructor(address adopter_, Phylax phylax_) {
        adopter = adopter_;
        phylax = phylax_;
    }

    function enable(uint256 value) external {
        assembly {
            sstore(ENABLED_SLOT, value)
        }
    }

    receive() external payable {}

    fallback(bytes calldata data) external payable returns (bytes memory) {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

        uint256 enabled;
        assembly {
            enabled := sload(ENABLED_SLOT)
        }
        console.log("Adopter");
        console.logAddress(address(adopter));
        console.log("Sender");
        console.logAddress(msg.sender);
        console.logUint(enabled);
        if (enabled == 0) {
            (bool success, bytes memory result) = address(adopter).delegatecall(msg.data);
            console.logBytes(result);

            return result;
        }
        assembly {
            sstore(ENABLED_SLOT, 0)
        }
        bool result = phylax.transact(msg.sender, address(this), msg.value, msg.data);
        if (enabled == 1) {
            require(result, "Assertion failed but expected to pass");
        } else if (enabled == 2) {
            require(!result, "Assertion passed but expected to fail");
        }
    }
}

contract Phylax {
    struct AssertionTransaction {
        address from;
        address to;
        uint256 value;
        bytes data;
    }

    VmEx public immutable vmEx;
    mapping(address => bytes[]) public adopters;
    mapping(address => address) public implementations;
    mapping(address => bool) public enabled;

    constructor(address vm_address) {
        vmEx = VmEx(vm_address);
    }

    function addAssertion(address assertionAdopter, bytes memory assertionCode, bytes memory constructorArgs)
        external
    {
        address proxy = address(new ProtocolProxy(address(0xabcabc), this));

        bytes memory runtimeCode;
        assembly {
            let size := extcodesize(assertionAdopter)
            runtimeCode := mload(0x40)
            mstore(0x40, add(runtimeCode, add(size, 0x20)))
            mstore(runtimeCode, size)
            extcodecopy(assertionAdopter, add(runtimeCode, 0x20), 0, size)
        }
        vmEx.etch(address(0xabcabc), runtimeCode);

        assembly {
            let size := extcodesize(proxy)
            runtimeCode := mload(0x40)
            mstore(0x40, add(runtimeCode, add(size, 0x20)))
            mstore(runtimeCode, size)
            extcodecopy(proxy, add(runtimeCode, 0x20), 0, size)
        }
        vmEx.etch(assertionAdopter, runtimeCode);

        adopters[assertionAdopter].push(abi.encodePacked(assertionCode, constructorArgs));
    }

    function expectValidation(address assertionAdopter) external {
        ProtocolProxy(payable(assertionAdopter)).enable(1);
    }

    function expectInvalidation(address assertionAdopter) external {
        ProtocolProxy(payable(assertionAdopter)).enable(2);
    }

    function getResult(address assertionAdopter) external view returns (bool) {
        return enabled[assertionAdopter];
    }

    function transact(address from, address to, uint256 value, bytes calldata data) external returns (bool) {
        console.log("transact");
        console.logAddress(from);
        console.logAddress(to);
        console.logUint(value);
        console.logBytes(data);
        return vmEx.assertionEx(
            abi.encode(AssertionTransaction({from: from, to: to, value: value, data: data})), to, adopters[to]
        );
    }
}

contract PhylaxTest is Test {
    Phylax phylax = new Phylax(VM_ADDRESS);
}
