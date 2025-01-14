// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Assertion} from "./Assertion.sol";

interface PhVm {
    struct AssertionTransaction {
        address from;
        address to;
        uint256 value;
        bytes data;
    }

    function assertionEx(
        bytes calldata tx,
        address assertionAdopter,
        bytes[] calldata assertions
    ) external returns (bool success);
}

contract AssertionTest is Test {
    PhVm phvm = PhVm(VM_ADDRESS);

    function createTransaction(
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes memory) {
        PhVm.AssertionTransaction memory txData = PhVm.AssertionTransaction({
            from: from,
            to: to,
            value: value,
            data: data
        });
        return abi.encode(txData);
    }

    function createEmptyTransaction() internal pure returns (bytes memory) {
        return
            abi.encode(
                PhVm.AssertionTransaction({
                    from: address(0),
                    to: address(0),
                    value: 0,
                    data: new bytes(0)
                })
            );
    }
}
