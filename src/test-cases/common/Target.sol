// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

Target constant TARGET = Target(
    address(0x8464135c8F25Da09e49BC8782676a84730C318bC)
);

contract Target {
    event Log(uint256 value);

    uint256 value = 1;

    function readStorage() external view returns (uint256) {
        return value;
    }

    function writeStorage(uint256 value_) public {
        value = value_;
        emit Log(value);
    }

    function incrementStorage() public {
        uint256 _value = value + 1;
        writeStorage(_value);
    }

    function writeStorageAndRevert(uint256 value_) external {
        writeStorage(value_);
        revert("revert from Target");
    }
}
