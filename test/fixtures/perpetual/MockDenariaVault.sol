// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IDenariaVaultLike} from "../../../src/protection/perpetual/examples/DenariaInterfaces.sol";

/// @title MockDenariaVault
/// @notice Minimal mock implementing the Denaria Vault interface surface used by the suite.
contract MockDenariaVault is IDenariaVaultLike {
    mapping(address => uint256) public collateral;

    function setCollateral(address user, uint256 amount) external {
        collateral[user] = amount;
    }

    function userCollateral(address user) external view override returns (uint256) {
        return collateral[user];
    }

    function removeCollateral(uint256 amount, bytes memory) external override {
        require(collateral[msg.sender] >= amount, "insufficient collateral");
        collateral[msg.sender] -= amount;
    }

    function removeAllCollateral(bytes memory) external override {
        collateral[msg.sender] = 0;
    }
}
