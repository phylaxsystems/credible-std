// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

Target constant TARGET = Target(payable(0xdCCf1eEB153eF28fdc3CF97d33f60576cF092e9c));

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

    receive() external payable {}
}
