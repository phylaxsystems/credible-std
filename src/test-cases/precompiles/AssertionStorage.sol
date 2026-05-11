// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";
import {Target, TARGET} from "../common/Target.sol";

contract TestAssertionStorage is Assertion {
    constructor() payable {}

    function storeAndLoadRoundtrips() external {
        bytes32 key = keccak256("assertion-storage-test/key-1");
        bytes32 value = bytes32(uint256(0xdeadbeef));

        ph.store(key, value);
        require(ph.load(key) == value, "load returned wrong value");
    }

    function existsReportsWrittenKeys() external {
        bytes32 missingKey = keccak256("assertion-storage-test/missing");
        require(!ph.exists(missingKey), "missing key should not exist");

        bytes32 key = keccak256("assertion-storage-test/key-2");
        ph.store(key, bytes32(uint256(1)));
        require(ph.exists(key), "key should exist after store");
    }

    function overwriteKeepsKeyExisting() external {
        bytes32 key = keccak256("assertion-storage-test/key-3");
        ph.store(key, bytes32(uint256(1)));
        ph.store(key, bytes32(uint256(2)));
        require(ph.load(key) == bytes32(uint256(2)), "overwrite did not stick");
        require(ph.exists(key), "key should still exist after overwrite");
    }

    function valuesLeftDecreasesAsKeysAreWritten() external {
        uint256 before_ = ph.values_left();
        bytes32 key = keccak256("assertion-storage-test/key-4");
        ph.store(key, bytes32(uint256(7)));
        uint256 after_ = ph.values_left();
        require(after_ < before_, "values_left did not decrease");
        require(before_ - after_ == 1, "values_left should drop by exactly 1");

        // Overwriting an existing key must not consume additional slots.
        ph.store(key, bytes32(uint256(8)));
        require(ph.values_left() == after_, "overwrite should not consume a slot");
    }

    function triggers() external view override {
        registerCallTrigger(this.storeAndLoadRoundtrips.selector);
        registerCallTrigger(this.existsReportsWrittenKeys.selector);
        registerCallTrigger(this.overwriteKeepsKeyExisting.selector);
        registerCallTrigger(this.valuesLeftDecreasesAsKeysAreWritten.selector);
    }
}

contract TriggeringTx {
    constructor() payable {
        TARGET.writeStorage(1);
    }
}
