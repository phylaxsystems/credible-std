// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "../../Assertion.sol";
import {PhEvm} from "../../PhEvm.sol";

contract MappingTarget {
    // slot 0
    mapping(address => uint256) public balances;

    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }
}

MappingTarget constant MAPPING_TARGET = MappingTarget(0xdCCf1eEB153eF28fdc3CF97d33f60576cF092e9c);

contract TestChangedMappingKeys is Assertion {
    constructor() payable {}

    function checkChangedKeys() external view {
        bytes[] memory keys = ph.changedMappingKeys(address(MAPPING_TARGET), bytes32(uint256(0)));
        require(keys.length == 2, "expected 2 changed keys");
    }

    function triggers() external view override {
        registerCallTrigger(this.checkChangedKeys.selector);
    }
}

contract TestMappingValueDiff is Assertion {
    constructor() payable {}

    function checkValueDiff() external view {
        address user = address(0xBEEF);
        bytes memory key = abi.encode(user);

        (bytes32 pre, bytes32 post, bool changed) =
            ph.mappingValueDiff(address(MAPPING_TARGET), bytes32(uint256(0)), key, 0);

        require(changed, "value should have changed");
        require(pre == bytes32(uint256(0)), "pre should be zero");
        require(post == bytes32(uint256(100)), "post should be 100");
    }

    function triggers() external view override {
        registerCallTrigger(this.checkValueDiff.selector);
    }
}

contract MappingTriggeringTx {
    constructor() payable {
        MAPPING_TARGET.setBalance(address(0xBEEF), 100);
        MAPPING_TARGET.setBalance(address(0xCAFE), 200);
    }
}
