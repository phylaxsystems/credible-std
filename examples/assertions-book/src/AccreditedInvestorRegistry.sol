// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract AccreditedInvestorRegistry {
    mapping(address => bool) public isAccredited;

    function setAccredited(address account, bool accredited) external {
        isAccredited[account] = accredited;
    }
}
